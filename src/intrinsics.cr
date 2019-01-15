lib LibIntrinsics
  fun debugtrap = "llvm.debugtrap"
  fun read_cycle_counter = "llvm.readcyclecounter" : UInt64
  fun bswap32 = "llvm.bswap.i32"(id : UInt32) : UInt32

  fun popcount8 = "llvm.ctpop.i8"(src : Int8) : Int8
  fun popcount16 = "llvm.ctpop.i16"(src : Int16) : Int16
  fun popcount32 = "llvm.ctpop.i32"(src : Int32) : Int32
  fun popcount64 = "llvm.ctpop.i64"(src : Int64) : Int64
  fun popcount128 = "llvm.ctpop.i128"(src : Int128) : Int128

  fun va_start = "llvm.va_start"(ap : Void*)
  fun va_end = "llvm.va_end"(ap : Void*)
end

module Intrinsics
  def self.debugtrap
    LibIntrinsics.debugtrap
  end

  @[Primitive(:memcpy)]
  def self.memcpy(dest : Void*, src : Void*, len, align : UInt32, is_volatile : Bool) : Void
  end

  @[Primitive(:memmove)]
  def self.memmove(dest : Void*, src : Void*, len, align : UInt32, is_volatile : Bool) : Void
  end

  @[Primitive(:memset)]
  def self.memset(dest : Void*, val : UInt8, len, align : UInt32, is_volatile : Bool) : Void
  end

  def self.read_cycle_counter
    LibIntrinsics.read_cycle_counter
  end

  def self.bswap32(id)
    LibIntrinsics.bswap32(id)
  end

  def self.popcount8(src)
    LibIntrinsics.popcount8(src)
  end

  def self.popcount16(src)
    LibIntrinsics.popcount16(src)
  end

  def self.popcount32(src)
    LibIntrinsics.popcount32(src)
  end

  def self.popcount64(src)
    LibIntrinsics.popcount64(src)
  end

  def self.popcount128(src)
    LibIntrinsics.popcount128(src)
  end

  def self.va_start(ap)
    LibIntrinsics.va_start(ap)
  end

  def self.va_end(ap)
    LibIntrinsics.va_end(ap)
  end
end

macro debugger
  Intrinsics.debugtrap
end
