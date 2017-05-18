require "../../spec_helper"

include ::Crystal::Inference

module Crystal::Inference
  module TypeHelper
    # Built it types

    def self.fresh
      ITypeVariable.fresh
    end

    def self.bool
      INamedType.new("::Bool")
    end

    def self.int32
      INamedType.new("::Int32")
    end

    def self.int64
      INamedType.new("::Int64")
    end

    def self.char
      INamedType.new("::Char")
    end

    def self.nil
      INamedType.new("::Nil")
    end

    def self.string
      INamedType.new("::String")
    end

    def self.symbol
      INamedType.new("::Symbol")
    end

    def self.func(arg : IType, ret)
      IFunctionType.new([arg] of IType, ret)
    end

    # Sample types

    def self.foo
      INamedType.new("::Foo")
    end

    def self.bar
      INamedType.new("::Bar")
    end
  end
end
