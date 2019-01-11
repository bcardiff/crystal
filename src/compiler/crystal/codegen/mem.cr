require "./codegen"

class Crystal::CodeGenVisitor
  def codegen_llvm_memcpy(dest : LLVM::Value, src : LLVM::Value, len : LLVM::Value, align : LLVM::Value, is_volatile : LLVM::Value)
    if @program.has_flag?("x86_64")
      llvm_fun = get_llvm_fun("llvm.memcpy.p0i8.p0i8.i64",
        [llvm_context.void_pointer, llvm_context.void_pointer, llvm_context.int64, llvm_context.int32, llvm_context.int1],
        llvm_context.void)

      len = llvm_mem_len_cast(len, llvm_context.int64)
    else
      llvm_fun = get_llvm_fun("llvm.memcpy.p0i8.p0i8.i32",
        [llvm_context.void_pointer, llvm_context.void_pointer, llvm_context.int32, llvm_context.int32, llvm_context.int1],
        llvm_context.void)

      len = llvm_mem_len_cast(len, llvm_context.int32)
    end

    builder.call(llvm_fun, [dest, src, len, align, is_volatile])
  end

  def codegen_llvm_memmove(dest : LLVM::Value, src : LLVM::Value, len : LLVM::Value, align : LLVM::Value, is_volatile : LLVM::Value)
    if @program.has_flag?("x86_64")
      llvm_fun = get_llvm_fun("llvm.memmove.p0i8.p0i8.i64",
        [llvm_context.void_pointer, llvm_context.void_pointer, llvm_context.int64, llvm_context.int32, llvm_context.int1],
        llvm_context.void)

      len = llvm_mem_len_cast(len, llvm_context.int64)
    else
      llvm_fun = get_llvm_fun("llvm.memmove.p0i8.p0i8.i32",
        [llvm_context.void_pointer, llvm_context.void_pointer, llvm_context.int32, llvm_context.int32, llvm_context.int1],
        llvm_context.void)

      len = llvm_mem_len_cast(len, llvm_context.int32)
    end

    builder.call(llvm_fun, [dest, src, len, align, is_volatile])
  end

  def codegen_llvm_memset(dest : LLVM::Value, val : LLVM::Value, len : LLVM::Value, align : LLVM::Value, is_volatile : LLVM::Value)
    if @program.has_flag?("x86_64")
      llvm_fun = get_llvm_fun("llvm.memset.p0i8.i64",
        [llvm_context.void_pointer, llvm_context.int8, llvm_context.int64, llvm_context.int32, llvm_context.int1],
        llvm_context.void)

      len = llvm_mem_len_cast(len, llvm_context.int64)
    else
      llvm_fun = get_llvm_fun("llvm.memset.p0i8.i32",
        [llvm_context.void_pointer, llvm_context.int8, llvm_context.int32, llvm_context.int32, llvm_context.int1],
        llvm_context.void)

      len = llvm_mem_len_cast(len, llvm_context.int32)
    end

    builder.call(llvm_fun, [dest, val, len, align, is_volatile])
  end

  # The `len` argument is UInt64 or UInt32 depending on the architecture.
  # llvm values don't have sign information so this function use the fact
  # the len argument should be unsigned.
  private def llvm_mem_len_cast(len, target_llvm_type)
    len_type = case len.type.int_width
               when 64
                 @program.uint64
               when 32
                 @program.uint32
               else
                 raise "Invalid len argument. Expected: UInt64 or UInt32, got #{len.type}"
               end

    target_type = case target_llvm_type.int_width
                  when 64
                    @program.uint64
                  when 32
                    @program.uint32
                  else
                    raise "unreachable!"
                  end

    codegen_cast(len_type, target_type, len)
  end

  private def get_llvm_fun(fun_name, args_type, return_type)
    llvm_mod.functions[fun_name]? ||
      llvm_mod.functions.add(fun_name, args_type, return_type)
  end
end
