# Here lies the logic of the representation of the MixedUnionType.
#
# Which structure is used to represent them is defined in `LLVMTyper#create_llvm_type`.
#
# The `#union_type_and_value_pointer` will allow to read the current value of the union.
# The `#store*_in_union` operations allow to write the value in a unions.
# The `#{assign|downcast|upcast}_distinct_union_types` operation matches the
# semantics described in `./casts.cr`
#
# Together these operations should encapsulate the binary representation of the MixedUnionType.
#
# Other unions like ReferenceUnionType that have a more trivial
# representation are not handled here.
#
module Crystal
  class Program
    enum UnionsStrategy
      Collapsed
      Expanded
      HLE
    end

    def unions_strategy
      if has_flag?("expanded_unions")
        UnionsStrategy::Expanded
      elsif has_flag?("hle_unions")
        UnionsStrategy::HLE
      else
        UnionsStrategy::Collapsed
      end
    end

    @all_concrete_types_cache = Hash(Crystal::Type, Set(Crystal::Type)).new

    def all_concrete_types(type : Crystal::Type)
      @all_concrete_types_cache[type] ||= find_all_concrete_types(type)
    end

    private def find_all_concrete_types(type : Crystal::Type)
      result = Set(Crystal::Type).new

      if type.is_a?(MultiType)
        result.concat(type.concrete_types)
      else
        result << type
      end

      return result
    end

    # payload array size used to store the union kind
    @mixed_unions_payload_size = Hash(MixedUnionType, Int32).new

    def set_mixed_union_payload_size(union_type : MixedUnionType, payload_size : Int32)
      raise "BUG: Unexpected call to set_mixed_union_payload_size. Program is being compiled with expanded unions." if @program.unions_strategy.expanded?

      @mixed_unions_payload_size[union_type] = payload_size
    end

    def mixed_union_payload_size(union_type : MixedUnionType)
      raise "BUG: Unexpected call to mixed_union_payload_size. Program is being compiled with expanded unions." if @program.unions_strategy.expanded?

      @mixed_unions_payload_size[union_type]
    end

    # Index of components for each type that the union can hold.
    # The cache is in program because LLVMTyper and CodeGenVisitors are created along
    # the compilation process. They struct are copied in LLVMTyper#copy_type but
    # there is no information about which MixedUnionType the struct represent
    # in order to pass from one codegen on LLVMTyper to another the struct and the indices.
    @mixed_unions_value_offsets = Hash(MixedUnionType, Hash(Type, Int32)).new

    def set_mixed_union_value_offsets(union_type : MixedUnionType, value_offsets = Hash(Type, Int32))
      raise "BUG: Unexpected call to set_mixed_union_value_offsets. Program is not being compiled with expanded unions." unless @program.unions_strategy.expanded?

      @mixed_unions_value_offsets[union_type] = value_offsets
    end

    def mixed_union_value_offset(union_type : MixedUnionType, type : Type) : Int32
      raise "BUG: Unexpected call to mixed_union_value_offset. Program is not being compiled with expanded unions." unless @program.unions_strategy.expanded?
      raise "BUG: looking for a value_offset for a union type #{type}." if type.is_a?(UnionType)

      # Since this is used in codegen, the semantic analysis should've
      # restrict the sound usage of the union.
      # For types that have a predefined component there is no need to
      # store them in the value_offsets hash.
      # Types like Nil and Void are actually stored in the value_offsets hash
      # since they do not expand to multiple types as references and metaclasses.
      return 1 if type.reference_like? && !type.nil_type?
      return -1 if type.metaclass?

      @mixed_unions_value_offsets[union_type].fetch(type) {
        raise "BUG: looking for component value for #{type} in a #{self}."
      }
    end

    def spin_init_hle(llvm_mod, llvm_context)
      llvm_mod.functions["spin_init_hle"]? || llvm_mod.functions.add("spin_init_hle", [llvm_context.int32.pointer], llvm_context.void)
    end

    def spin_lock_hle(llvm_mod, llvm_context)
      llvm_mod.functions["spin_lock_hle"]? || llvm_mod.functions.add("spin_lock_hle", [llvm_context.int32.pointer], llvm_context.void)
    end

    def spin_unlock_hle(llvm_mod, llvm_context)
      llvm_mod.functions["spin_unlock_hle"]? || llvm_mod.functions.add("spin_unlock_hle", [llvm_context.int32.pointer], llvm_context.void)
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

        case @program.unions_strategy
        when .collapsed?, .hle?
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
          @program.set_mixed_union_payload_size(type, max_size)

          if @program.unions_strategy.collapsed?
            [@llvm_context.int32, llvm_value_type]
          else
            [@llvm_context.int32, llvm_value_type, @llvm_context.int32]
          end
        when .expanded?
          value_offsets = Hash(Type, Int32).new
          @program.set_mixed_union_value_offsets(type, value_offsets)

          res = [@llvm_context.int32] # The first component holds the type_id

          all_concrete_types = @program.all_concrete_types(type).to_a.sort_by! { |t|
            type_repr_order(t)
          }

          has_not_nil_reference_like = all_concrete_types.any? { |t| t.reference_like? && !t.nil_type? }

          res << @llvm_context.int32.pointer if has_not_nil_reference_like

          all_concrete_types.each do |subtype|
            case subtype
            when .void?
              # VoidType is mapped to -1 if void is allowed as value.
              value_offsets[subtype] = -1
            when .nil_type?
              # NilType is mapped to -1 if nil is allowed as value.
              value_offsets[subtype] = -1
            when .reference_like?
              # non nilable references are stored always after type_id component
              # See MixedUnionType#value_offset
            when .metaclass?
              # metaclass representation is not used, but required to exist.
              # See MixedUnionType#value_offset
            else
              value_offsets[subtype] = res.size
              repr = llvm_embedded_type(subtype).as(LLVM::Type)
              res << repr
            end
          end

          res
        else
          raise "unreachable"
        end
      end
    end

    private def type_repr_order(t : Type) : {Int32, Int32}
      # We need a total order that will have a deterministic evaluation accross different
      # LLVMTyper over the same program. Between equal sizes, the type_id will dissambiguate.

      size = self.size_of(self.llvm_type(t, wants_size: true)).to_i32.as(Int32)
      {size, @program.llvm_id.type_id(t)}
    end

    def union_value_type(type : MixedUnionType)
      raise "BUG: Unexpected call to union_value_type. Program is being compiled with expanded unions." if @program.unions_strategy.expanded?
      llvm_type(type).struct_element_types[1]
    end
  end

  class CodeGenVisitor
    def union_lock_pointer(union_pointer)
      case @program.unions_strategy
      when .hle?
        aggregate_index(union_pointer, 2)
      else
        raise "BUG: union_lock_pointer called with no lock union strategy"
      end
    end

    def union_lock_init(union_pointer)
      case @program.unions_strategy
      when .hle?
        codegen_call_spin_init_hle(union_lock_pointer(union_pointer))
      end
    end

    def codegen_call_spin_init_hle(ptr)
      call @program.spin_init_hle(@llvm_mod, llvm_context), [ptr]
    end

    @@lock_count = 0

    def codegen_call_spin_lock_hle(ptr)
      @@lock_count &+= 1
      debug_codegen_log { "lock-num: #{@@lock_count}\n" } # + caller[0..5].join("\n") }
      call @program.spin_lock_hle(@llvm_mod, llvm_context), [ptr]
    end

    def codegen_call_spin_unlock_hle(ptr)
      # debug_codegen_log { caller[0..5].join("\n") }
      call @program.spin_unlock_hle(@llvm_mod, llvm_context), [ptr]
    end

    def union_lock_lock(union_pointer, type : UnionType)
      # There is no lock for UnionType, only for MixedUnionType
    end

    def union_lock_lock(union_pointer, type : MixedUnionType)
      case @program.unions_strategy
      when .hle?
        codegen_call_spin_lock_hle union_lock_pointer(union_pointer)
      end
    end

    def union_lock_unlock(union_pointer, type : UnionType)
      # There is no unlock for UnionType, only for MixedUnionType
    end

    def union_lock_unlock(union_pointer, type : MixedUnionType)
      case @program.unions_strategy
      when .hle?
        codegen_call_spin_unlock_hle union_lock_pointer(union_pointer)
      end
    end

    def union_lock_synchronize(union_pointer, type : MixedUnionType)
      case @program.unions_strategy
      when .hle?
        lock_pointer = union_lock_pointer(union_pointer)
        codegen_call_spin_lock_hle lock_pointer
        res = yield
        codegen_call_spin_unlock_hle lock_pointer
        res
      else
        yield
      end
    end

    def union_lock_synchronize(union_pointer, type : UnionType)
      # There is no unlock for UnionType, only for MixedUnionType
      yield
    end

    def union_type_and_value_pointer(union_pointer, type : UnionType)
      raise "BUG: trying to access union_type_and_value_pointer of a #{type} from #{union_pointer}"
    end

    def union_type_and_value_pointer(union_pointer, type : MixedUnionType)
      case @program.unions_strategy
      when .collapsed?
        # In compacted (legacy) unions the value is stored always in the same place and the type id
        # is stored explictly in the first component
        {load(union_type_id(union_pointer)), union_value(union_pointer)}
      when .hle?
        # create a copy of the type_id and raw value within a lock/unlock section.
        # Return the values that were thread-safetely read
        type_id = llvm_alloca(llvm_context.int32)
        raw_value = llvm_alloca(llvm_typer.size_t.array(@program.mixed_union_payload_size(type)))
        # debug_codegen_log { raw_value.to_s }

        union_lock_synchronize(union_pointer, type) do
          store load(union_type_id(union_pointer)), type_id
          store load(union_value(union_pointer)), raw_value
        end

        {load(type_id), raw_value}
      when .expanded?
        # In expanded unions the type id defines in which component the value needs to be looked up.
        # In case of a reference, the actual type id is stored in the first component of the referenced value.
        # Since this method returns a pointer where the value is referenced we use a stack allocated pointer
        # to ensure that it will remain available and consistent with the returned type id.
        # The result of this method is used only for reading operations.

        stored_type_id = load(union_type_id(union_pointer))

        current_block = insert_block
        exit_block = new_block "union_type_and_value_pointer_exit"
        type_id_phi_table = LLVM::PhiTable.new
        value_pointer_phi_table = LLVM::PhiTable.new

        cases = {} of LLVM::Value => LLVM::BasicBlock

        subtype_reference_block_generated = false
        type_id_only_values_block = nil

        all_concrete_types = @program.all_concrete_types(type)

        all_concrete_types.each do |subtype|
          value_offset = @program.mixed_union_value_offset(type, subtype)

          if subtype.reference_like? && !subtype.nil_type?
            # we only need to generate the reference value branch once
            next if subtype_reference_block_generated
            subtype_reference_block_generated = true

            cases[type_id(@program.reference)] = begin
              block = new_block "subtype_reference"
              position_at_end block

              reference_value_ptr = aggregate_index(union_pointer, @program.mixed_union_value_offset(type, @program.reference))
              reference_value = load(reference_value_ptr)
              reference_value_ptr_copy = llvm_alloca(llvm_typer.size_t.pointer)

              if all_concrete_types.any?(&.nil_type?)
                # only include fallback to read a nil value if the
                # union is allowed to store it
                pointer_not_null = not_null_pointer?(reference_value)
                not_null_reference_block = new_block "subtype_reference_not_null"
                null_reference_block = new_block "subtype_reference_null"
                cond pointer_not_null, not_null_reference_block, null_reference_block

                position_at_end null_reference_block
                type_id_phi_table.add insert_block, type_id(@program.nil)
                value_pointer_phi_table.add insert_block, casted_global_zeroed_value
                br exit_block

                position_at_end not_null_reference_block
              end

              store bit_cast(reference_value, llvm_typer.size_t.pointer), reference_value_ptr_copy

              # load the actual type id stored in first component of the reference type
              type_id_phi_table.add insert_block, load(reference_value)
              # cast the double pointer to an opaque pointer to match the same type accross the PHI
              value_pointer_phi_table.add insert_block, bit_cast(reference_value_ptr_copy, llvm_typer.size_t.pointer)

              br exit_block
              block
            end
          elsif value_offset == -1
            # all the types that their representation is only the type-id like nil, void and metaclasses
            # can have the same block
            cases[type_id(subtype)] = type_id_only_values_block ||= begin
              block = new_block "subtype_type_id_only_value"
              position_at_end block

              type_id_phi_table.add insert_block, stored_type_id
              value_pointer_phi_table.add insert_block, casted_global_zeroed_value

              br exit_block
              block
            end
          else
            cases[type_id(subtype)] = begin
              block = new_block "subtype_#{subtype}"
              position_at_end block

              value_ptr = bit_cast(aggregate_index(union_pointer, value_offset), llvm_typer.size_t.pointer)

              type_id_phi_table.add insert_block, stored_type_id
              value_pointer_phi_table.add insert_block, value_ptr

              br exit_block
              block
            end
          end
        end

        otherwise = new_block "union_type_and_value_pointer_unreachable"
        position_at_end otherwise
        unreachable

        position_at_end current_block
        switch stored_type_id, otherwise, cases

        position_at_end exit_block
        actual_type_id = phi llvm_context.int32, type_id_phi_table
        actual_value_pointer = phi llvm_typer.size_t.pointer, value_pointer_phi_table

        {actual_type_id, actual_value_pointer}
      else
        raise "unreachable"
      end
    end

    private def casted_global_zeroed_value
      bit_cast(global_zeroed_value, llvm_typer.size_t.pointer)
    end

    private def global_zeroed_value
      res = @llvm_mod.globals["global_zeroed_value"]?

      if res.nil?
        res = @llvm_mod.globals.add(llvm_typer.nil_type, "global_zeroed_value")
        res.linkage = LLVM::Linkage::Private
        res.initializer = llvm_typer.nil_value
        res.global_constant = true
      end

      res
    end

    def type_id_and_value(value, type)
      case
      when PrimitiveType, PointerInstanceType, ProcInstanceType
        {type_id(value, type), value, false}
      when type.passed_by_value?
        {type_id(value, type), load(value), false}
      else
        {type_id(value, type), value, false}
      end
    end

    def type_id_and_value(value, type : MixedUnionType)
      type_id, value_ptr = union_type_and_value_pointer(value, type)
      {type_id, value_ptr, true}
    end

    def union_type_id(union_pointer)
      aggregate_index union_pointer, 0
    end

    def union_value(union_pointer)
      raise "BUG: Unexpected call to union_value. Program is being compiled with expanded unions." if @program.unions_strategy.expanded?
      aggregate_index union_pointer, 1
    end

    def store_in_union(union_type, union_pointer, value_type, value)
      case @program.unions_strategy
      when .collapsed?, .hle?
        # issue about value been sometimes ref sometimes val? type_id has a lock... but the value...
        if value_type.is_a?(MixedUnionType)
          # puts caller.join("\n         ")
          # pp! union_type, union_pointer, value_type, value
          # debug_codegen_log { value_type.to_s + value.to_s + caller[0..5].join("\n") }
          value_type_id, value_raw_ptr = union_type_and_value_pointer(value, value_type)
          value_raw = load(value_raw_ptr)
          # value_raw = value                          # when storing a union the value is the LLVM::Value already ....
          # value_type_id = type_id(value, value_type) # the type is extracted from the llvm::value... it's odd
          casted_value_ptr = union_value(union_pointer)
        else
          value_type_id = type_id(value, value_type)
          casted_value_ptr = cast_to_pointer(union_value(union_pointer), value_type)
          value_raw = value
        end

        union_lock_synchronize(union_pointer, union_type) do
          store value_type_id, union_type_id(union_pointer)
          # debug_codegen_log { value_type.class.to_s }
          # debug_codegen_log { caller[0..5].join("\n") }
          store value_raw, casted_value_ptr
        end
      when .expanded?
        mutual_types = @program.all_concrete_types(union_type) & @program.all_concrete_types(value_type)

        # This check can't be added becuase the mutual_types might be empty
        # if the actual mutual types would have been metaclasses regarding different
        # levels of the hierarchy.
        #
        # if mutual_types.empty?
        #   raise "BUG: Unable to find overlapping types between #{@program.all_concrete_types(union_type)} and #{@program.all_concrete_types(value_type)}"
        # end

        actual_value_type_id, actual_value, is_generic_pointer = type_id_and_value(value, value_type)

        current_block = insert_block
        exit_block = new_block "store_in_union_exit"
        reference_subtype = nil
        type_id_only_value_subtype = nil

        cases = {} of LLVM::Value => LLVM::BasicBlock
        mutual_types.each do |subtype|
          value_offset = @program.mixed_union_value_offset(union_type, subtype)

          if subtype.nil_type?
            cases[type_id(subtype)] = begin
              subtype_block = new_block "store_in_union_nil"
              position_at_end subtype_block

              store_nil_in_union(union_pointer, union_type)
              br exit_block

              subtype_block
            end
          elsif subtype.reference_like?
            cases[type_id(subtype)] = reference_subtype ||= begin
              reference_block = new_block "store_in_union_not_null_reference"
              position_at_end reference_block

              value_component = aggregate_index(union_pointer, @program.mixed_union_value_offset(union_type, @program.reference))
              if is_generic_pointer
                store_volatile load(bit_cast(actual_value, @llvm_context.int32.pointer.pointer)), value_component
              else
                store_volatile bit_cast(actual_value, @llvm_context.int32.pointer), value_component
              end
              store_volatile type_id(@program.reference), union_type_id(union_pointer)
              br exit_block

              reference_block
            end
          elsif subtype.void?
            cases[type_id(subtype)] = begin
              subtype_block = new_block "store_in_union_void"
              position_at_end subtype_block

              store_void_in_union(union_pointer, union_type)
              br exit_block

              subtype_block
            end
          elsif value_offset == -1
            # metaclass only since void and nil are handled separately since
            # there are store_nil_in_union and store_void_in_union operations
            cases[type_id(subtype)] = type_id_only_value_subtype ||= begin
              subtype_block = new_block "subtype_type_id_only_value"
              position_at_end subtype_block

              store actual_value_type_id, union_type_id(union_pointer)
              br exit_block

              subtype_block
            end
          else
            cases[type_id(subtype)] = begin
              subtype_block = new_block "store_in_union_#{subtype}"
              position_at_end subtype_block

              value_component = aggregate_index(union_pointer, value_offset)

              if is_generic_pointer
                store_volatile load(cast_to_pointer(actual_value, subtype)), value_component
              else
                store_volatile actual_value, value_component
              end
              store_volatile type_id(subtype), union_type_id(union_pointer)

              br exit_block

              subtype_block
            end
          end
        end

        otherwise = new_block "store_in_union_unreachable"
        position_at_end otherwise
        unreachable

        position_at_end current_block
        switch actual_value_type_id, otherwise, cases

        position_at_end exit_block
      else
        raise "unreachable"
      end
    end

    def store_bool_in_union(union_type, union_pointer, value)
      case @program.unions_strategy
      when .collapsed?, .hle?
        union_lock_synchronize(union_pointer, union_type) do
          store type_id(value, @program.bool), union_type_id(union_pointer)

          # To store a boolean in a union
          # we sign-extend it to the size in bits of the union
          union_value_type = @llvm_typer.union_value_type(union_type)
          union_size = @llvm_typer.size_of(union_value_type)
          int_type = llvm_context.int((union_size * 8).to_i32)

          bool_as_extended_int = builder.zext(value, int_type)
          casted_value_ptr = bit_cast(union_value(union_pointer), int_type.pointer)
          store bool_as_extended_int, casted_value_ptr
        end
      when .expanded?
        store_in_union(union_type, union_pointer, @program.bool, value)
      else
        raise "unreachable"
      end
    end

    def store_nil_in_union(union_pointer, target_type)
      case @program.unions_strategy
      when .collapsed?, .hle?
        union_lock_synchronize(union_pointer, target_type) do
          union_value_type = @llvm_typer.union_value_type(target_type)
          value = union_value_type.null

          store type_id(value, @program.nil), union_type_id(union_pointer)
          casted_value_ptr = bit_cast union_value(union_pointer), union_value_type.pointer
          store value, casted_value_ptr
        end
      when .expanded?
        # Clean up reference component (if exists) to help GC.
        has_not_nil_reference_like = @program.all_concrete_types(target_type).any? { |t| t.reference_like? && !t.nil_type? }
        if has_not_nil_reference_like
          reference_component = aggregate_index(union_pointer, @program.mixed_union_value_offset(target_type, @program.reference))
          store_volatile @llvm_context.int32.pointer.null, reference_component
        end

        store_volatile type_id(@program.nil), union_type_id(union_pointer)
      else
        raise "unreachable"
      end
    end

    def store_void_in_union(union_pointer, target_type)
      store type_id(@program.void), union_type_id(union_pointer)
    end

    def assign_distinct_union_types(target_pointer, target_type, value_type, value)
      case @program.unions_strategy
      when .collapsed?, .hle?
        casted_value = cast_to_pointer value, target_type
        store load(casted_value), target_pointer
      when .hle?
        union_lock_synchronize(target_pointer, target_type) do
          # TODO might need to store value and type independantly here. is value_type leaf value?
          casted_value = cast_to_pointer value, target_type
          store load(casted_value), target_pointer
        end
      when .expanded?
        store_in_union target_type, target_pointer, value_type, value
      else
        raise "unreachable"
      end
    end

    def downcast_distinct_union_types(value, to_type : MixedUnionType, from_type : MixedUnionType)
      # locked in caller in cast.cr
      case @program.unions_strategy
      when .collapsed?, .hle?
        cast_to_pointer value, to_type
      when .expanded?
        union_ptr = declare_value_storage(to_type)
        store_in_union to_type, union_ptr, from_type, value
        union_ptr
      else
        raise "unreachable"
      end
    end

    def upcast_distinct_union_types(value, to_type : MixedUnionType, from_type : MixedUnionType)
      case @program.unions_strategy
      when .collapsed?, .hle?
        # TODO should be locked outside, together with the typeid
        cast_to_pointer value, to_type
      when .expanded?
        union_ptr = declare_value_storage(to_type)
        store_in_union to_type, union_ptr, from_type, value
        union_ptr
      else
        raise "unreachable"
      end
    end

    private def type_id_impl(value, type : MixedUnionType)
      union_type_and_value_pointer(value, type)[0]
    end
  end
end
