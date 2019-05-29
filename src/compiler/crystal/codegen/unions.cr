module Crystal
  class Program
    def expanded_unions?
      has_flag?("preview_mt") || has_flag?("expanded_unions")
    end
  end

  class MixedUnionType
    # Index of components for each type that the union can hold.
    property! value_offsets : Hash(Type, Int32)

    def value_offset(type : Type) : Int32
      # TODO assert type is non-union

      # non nilable references are stored always after type_id component
      # Since this is used in codegen, the semantic analysis should've
      # restrict the sound usage of the union.
      # For convenient, a metaclass has a minimal representation. The same pointer
      # is reused.
      return 1 if (type.reference_like? && !type.nil_type?) || type.metaclass?

      value_offsets.fetch(type) {
        raise "BUG: looking for component value for #{type} in a #{self}."
      }
    end
  end

  class LLVMTyper
    private def create_llvm_type(type : MixedUnionType, wants_size)
      llvm_name = llvm_name(type, wants_size)
      if s = @structs[llvm_name]?
        return s
      end

      @llvm_context.struct(llvm_name) do |a_struct|
        if wants_size
          @wants_size_cache[type] = a_struct
        else
          @cache[type] = a_struct
          @structs[llvm_name] = a_struct
        end

        unless @program.expanded_unions?
          max_size = 0
          type.expand_union_types.each do |subtype|
            unless subtype.void?
              size = size_of(llvm_type(subtype, wants_size: true))
              max_size = size if size > max_size
            end
          end

          max_size /= pointer_size.to_f
          max_size = max_size.ceil.to_i

          max_size = 1 if max_size == 0

          llvm_value_type = size_t.array(max_size)

          if wants_size
            @wants_size_union_value_cache[type] = llvm_value_type
          else
            @union_value_cache[type] = llvm_value_type
          end

          [@llvm_context.int32, llvm_value_type]
        else
          # TODO check if other than MixedUnionType are actually used
          res = [@llvm_context.int32] # type_id
          type.value_offsets = value_offsets = Hash(Type, Int32).new

          # Collect all concrete types
          all_concrete_types = Set(Type).new
          type.expand_union_types.each do |subtype|
            subtype = subtype.remove_indirection

            if subtype.responds_to?(:concrete_types)
              subtype.concrete_types.each do |concrete_subtype|
                all_concrete_types << concrete_subtype
              end
            else
              all_concrete_types << subtype
            end
          end

          has_not_nil_reference_like = all_concrete_types.any? { |t|
            (t.reference_like? && !t.nil_type?) || t.metaclass?
          }

          res << @llvm_context.int32.pointer if has_not_nil_reference_like

          # TODO build unions of unions with reference type via aliases to check that references are understood

          all_concrete_types.each do |subtype|
            case subtype
            when .nil_type?
              # NilType is mapped to -1 if nils are allowed as values.
              value_offsets[subtype] = -1
            when .reference_like?
              # non nilable references are stored always after type_id component
              # See MixedUnionType#value_offset
            when .metaclass?
              # metaclass representation is not used, but required to exist.
              # See MixedUnionType#value_offset
            else
              value_offsets[subtype] = res.size
              size = llvm_embedded_type(subtype).as(LLVM::Type)
              res << size
            end
          end

          # TODO handle union_value_cache. why the type_id component is not included?
          #
          # if wants_size
          #   @wants_size_union_value_cache[type] = llvm_value_type
          # else
          #   @union_value_cache[type] = llvm_value_type
          # end

          res
        end
      end
    end
  end

  class CodeGenVisitor
    def union_type_id(union_pointer)
      aggregate_index union_pointer, 0
    end

    # Returns access to pointer to the representation struct of the union
    # that can hold a value_type.
    # Depending on the codegen of the union it might need a cast before
    # using it as a value_type directly.
    #
    # See `#union_value_pointer`
    def union_value_struct_pointer(union_pointer, union_type : MixedUnionType, value_type : Type)
      unless @program.expanded_unions?
        aggregate_index union_pointer, 1
      else
        # TODO value_type might be a NilableType, might need to adapt value_type
        aggregate_index union_pointer, union_type.value_offset(value_type)
      end
    end

    # Returns access to a pointer that can hold a value_type within the specified union.
    #
    # See `#union_value_struct_pointer`
    def union_value_pointer(union_pointer, union_type : MixedUnionType, value_type : Type)
      cast_to_pointer(union_value_struct_pointer(union_pointer, union_type, value_type), value_type)
    end

    def store_in_union(union_type : MixedUnionType, union_pointer, value_type : Type, value)
      # TODO assert value_type is a non-union
      unless @program.expanded_unions?
        store type_id(value, value_type), union_type_id(union_pointer)
        store value, union_value_pointer(union_pointer, union_type, value_type)
      else
        case
        when value_type.reference_like?
          store bit_cast(value, @llvm_context.int32.pointer), union_value_struct_pointer(union_pointer, union_type, @program.reference)
          store type_id(@program.reference), union_type_id(union_pointer)
        when value_type.struct? && value_type.abstract? && value_type.responds_to?(:subclasses)
          union_of_concrete_types = @program.union_of(value_type.subclasses)
          raise "BUG: expanding abstract struct without subclasses #{value_type}" unless union_of_concrete_types
          store_in_union(union_type, union_pointer, union_of_concrete_types, value)
        else
          store value, union_value_pointer(union_pointer, union_type, value_type)
          store type_id(value, value_type), union_type_id(union_pointer)
        end
      end
    end

    def store_in_union(union_type : MixedUnionType, union_pointer, value_type : UnionType, value)
      unless @program.expanded_unions?
        store type_id(value, value_type), union_type_id(union_pointer)
        store value, union_value_pointer(union_pointer, union_type, value_type)
      else
        current_block = insert_block
        exit = new_block "store_in_union_exit"

        cases = {} of LLVM::Value => LLVM::BasicBlock
        subtype_reference = nil

        value_type.expand_union_types.each do |subtype|
          if subtype.reference_like? && !subtype.nil_type?
            # the implementation to assign all reference type values
            # yields to the same code, they could be de-duplicated.
            subtype_reference ||= begin
              block = new_block "subtype_reference"
              position_at_end block
              store_in_union(union_type, union_pointer, @program.reference, value)
              br exit

              block
            end

            cases[type_id(subtype)] = subtype_reference
          else
            block = new_block "subtype_#{subtype}"
            position_at_end block
            store_in_union(union_type, union_pointer, subtype, value)
            br exit

            cases[type_id(subtype)] = block
          end
        end

        otherwise = new_block "store_in_union_unreachable"
        position_at_end otherwise
        unreachable

        position_at_end current_block
        switch type_id(value, value_type), otherwise, cases
        position_at_end exit
      end
    end

    def store_in_union(union_type : MixedUnionType, union_pointer, value_type : NilType, value)
      unless @program.expanded_unions?
        raise "BUG: unreachable"
      else
        store type_id(@program.nil), union_type_id(union_pointer)
      end
    end

    def store_bool_in_union(union_type, union_pointer, value)
      unless @program.expanded_unions?
        store type_id(value, @program.bool), union_type_id(union_pointer)

        # To store a boolean in a union
        # we sign-extend it to the size in bits of the union
        union_value_type = llvm_union_value_type(union_type)
        union_size = @llvm_typer.size_of(union_value_type)
        int_type = llvm_context.int((union_size * 8).to_i32)

        bool_as_extended_int = builder.zext(value, int_type)
        casted_value_ptr = bit_cast(union_value_struct_pointer(union_pointer, union_type, @program.bool), int_type.pointer)
        store bool_as_extended_int, casted_value_ptr
      else
        store_in_union(union_type, union_pointer, @program.bool, value)
      end
    end

    def store_nil_in_union(union_pointer, target_type)
      unless @program.expanded_unions?
        union_value_type = llvm_union_value_type(target_type)
        value = union_value_type.null

        store type_id(value, @program.nil), union_type_id(union_pointer)
        casted_value_ptr = bit_cast union_value_struct_pointer(union_pointer, target_type, @program.nil), union_value_type.pointer
        store value, casted_value_ptr
      else
        store type_id(@program.nil), union_type_id(union_pointer)
      end
    end

    private def type_id_impl(value, type : MixedUnionType)
      unless @program.expanded_unions?
        load(union_type_id(value))
      else
        stored_type_id = load(union_type_id(value))

        reference_block, exit_block = new_blocks "reference", "exit"
        phi_table = LLVM::PhiTable.new

        # If the value at stored_type_id is not type_id(@program.reference)
        # the value can be used directly as the type_id of the value in the union (exit_block),
        # otherwise we need to dereference that value (reference_block).
        # All reference types will hold a type id as first component in the struct,
        # hence casting the pointer to a i32** is valid.

        cond equal?(type_id(@program.reference), stored_type_id), reference_block, exit_block
        phi_table.add insert_block, stored_type_id

        position_at_end reference_block
        casted_value_ptr = bit_cast(union_value_struct_pointer(value, type, @program.reference), @llvm_context.int32.pointer.pointer)
        phi_table.add insert_block, load(load(casted_value_ptr))
        br exit_block

        position_at_end exit_block
        phi llvm_context.int32, phi_table
      end
    end

    def downcast_distinct(value, to_type : NilableType, from_type : MixedUnionType)
      unless @program.expanded_unions?
        load union_value_pointer(value, from_type, to_type)
      else
        stored_type_id = load(union_type_id(value))

        not_nil_block, exit_block = new_blocks "not_nil", "exit"
        phi_table = LLVM::PhiTable.new

        cond equal?(type_id(@program.nil), stored_type_id), exit_block, not_nil_block
        phi_table.add insert_block, llvm_type(to_type).null

        position_at_end not_nil_block
        phi_table.add insert_block, load(union_value_pointer(value, from_type, to_type))
        br exit_block

        position_at_end exit_block
        phi llvm_type(to_type), phi_table
      end
    end
  end
end
