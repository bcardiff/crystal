# Visual C++ Build Tools
# $ make clean crystal && DUMP=1 ./bin/crystal build win-raise.cr --cross-compile --target "x86_64-pc-windows-msvc19.0.0" --prelude=empty --ll
# D:\> link win-raise.o -defaultlib:libcmt
# D:\> win-raise.exe
# ABCDEYZ

lib LibC
  fun putchar(c : UInt8)
end

lib LibWindows
  fun cxx_throw_exception = _CxxThrowException(pExceptionObject : Void*, pThrowInfo : Void*) : NoReturn
end

module WindowsExt
  @[Primitive(:throw_info)]
  def self.throw_info : Void*
  end
end

@[Raises]
fun __crystal_raise(ex : Void*) : NoReturn
  LibC.putchar 67u8
  ti = WindowsExt.throw_info.as(Pointer({Int32, Int32, Int32, Int32}))
  LibC.putchar 68u8
  LibWindows.cxx_throw_exception(ex, ti)
end

def raise(ex : Exception) : NoReturn
  __crystal_raise(pointerof(ex).as(Void*))
end

class Exception
  def message
    @message
  end

  def initialize(@message : UInt8)
  end
end

LibC.putchar 65u8
begin
  LibC.putchar 66u8
  raise Exception.new(69u8)
rescue e : Exception
  LibC.putchar e.message
  LibC.putchar 89u8
end
LibC.putchar 90u8
LibC.putchar 10u8
