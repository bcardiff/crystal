module Crystal
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
      end
    end
  end

  class CodeGenVisitor
    def union_type_id(union_pointer)
      aggregate_index union_pointer, 0
    end

    def union_value(union_pointer)
      aggregate_index union_pointer, 1
    end

    def store_in_union(union_pointer, value_type, value)
      store type_id(value, value_type), union_type_id(union_pointer)
      casted_value_ptr = cast_to_pointer(union_value(union_pointer), value_type)
      store value, casted_value_ptr
    end

    def store_bool_in_union(union_type, union_pointer, value)
      store type_id(value, @program.bool), union_type_id(union_pointer)

      # To store a boolean in a union
      # we sign-extend it to the size in bits of the union
      union_value_type = llvm_union_value_type(union_type)
      union_size = @llvm_typer.size_of(union_value_type)
      int_type = llvm_context.int((union_size * 8).to_i32)

      bool_as_extended_int = builder.zext(value, int_type)
      casted_value_ptr = bit_cast(union_value(union_pointer), int_type.pointer)
      store bool_as_extended_int, casted_value_ptr
    end

    def store_nil_in_union(union_pointer, target_type)
      union_value_type = llvm_union_value_type(target_type)
      value = union_value_type.null

      store type_id(value, @program.nil), union_type_id(union_pointer)
      casted_value_ptr = bit_cast union_value(union_pointer), union_value_type.pointer
      store value, casted_value_ptr
    end
  end
end
