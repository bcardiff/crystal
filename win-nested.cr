lib LibC
  fun putchar(c : UInt8) : Void
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
  ti = WindowsExt.throw_info.as(Pointer({Int32, Int32, Int32, Int32}))
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
  begin
    LibC.putchar 67u8
    raise Exception.new(33u8)
  rescue e
    LibC.putchar e.message
    LibC.putchar 88u8
    raise e
  end
rescue e
  LibC.putchar e.message
  LibC.putchar 89u8
end
LibC.putchar 90u8
LibC.putchar 10u8
