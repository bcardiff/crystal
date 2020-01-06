abstract class Crystal::ValueHolder
  # Creates a `ValueHolder` to storage a value with the given *crystal_type*.
  #
  # The value is assumed that will be neither shared, nor accessed concurrently.
  #
  # An LLVM `alloca` will be emitted in the alloca section.
  def self.init_owned_mutable_value(codegen : CodeGenVisitor, crystal_type : Type, name = "")
    pointer = codegen.alloca(codegen.llvm_type(type), name)
    OwnedMutableValueHolder.new(pointer, crystal_type)
  end

  # Creates a `ValueHolder` to use the *pointer* as a storage
  # of a value with the given *crystal_type*.
  #
  # The value is assumed that can be shared and accessed concurrently.
  def self.create_shared_mutable_value(codegen : CodeGenVisitor, pointer : LLVM::Value, crystal_type : Type)
    SharedMutableValueHolder.new(pointer, crystal_type)
  end

  # Returns a read-only representation of the value.
  # Might not generate llvm code while returning itself directly
  # or a reinterpretation of the underlying llvm value.
  abstract def read : ReadOnlyValueHolder

  # TODO abstract def upcast(crystal_type : Type)
end

module Crystal::ReadOnlyValueHolder
end

module Crystal::ReferenceBackedValueHolder
  # Stores a value in *self*
  def write(value : ValueHolder)
  end
end

# A value that is represented by a llvm pointer.
# The value CAN be accesed concurrently.
# Used for closured variables.
#
# ```llvm-ir
# %temp_0 = call i8* @malloc(i32 4)
# %pointer = bitcast i8* %temp_0 to i32*
# ;; *crystal_type* can be Int32 or UInt32
# ```
class Crystal::SharedMutableValueHolder < Crystal::ValueHolder
  getter pointer : LLVM::Value
  getter crystal_type : Type

  include ReferenceBackedValueHolder
end

# A value that is represented by a llvm pointer.
# The value CAN'T be accesed concurrently.
# Used for local variables.
#
# ```llvm-ir
# %pointer = alloca i32
# ;; *crystal_type* can be Int32 or UInt32
# ```
class Crystal::OwnedMutableValueHolder < Crystal::ValueHolder
  getter pointer : LLVM::Value
  getter crystal_type : Type

  include ReferenceBackedValueHolder
end

# A value that is represented by a llvm pointer and is not expected to be written.
# Might be used to store a load of an intermediate value.
#
# ```llvm-ir
# %pointer = alloca i32
# ```
class Crystal::ReferenceReadOnlyValueHolder < Crystal::ValueHolder
  include ReadOnlyValueHolder
end

# A value that is represented directly as a llvm value
#
# ```llvm-ir
# %value = i32 10
# ;; *crystal_type* can be Int32 or UInt32
# ```
class Crystal::RawValueReadOnlyValueHolder < Crystal::ValueHolder
  include ReadOnlyValueHolder

  getter value : LLVM::Value
  getter crystal_type : Type
end
