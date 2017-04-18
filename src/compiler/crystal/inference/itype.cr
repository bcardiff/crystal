module Crystal::Inference
  alias IType = INamedType | ITypeVariable | IUnion | IFunctionType

  class INamedType
    # TODO handle generics
    getter name : String

    def initialize(@name)
    end

    def self.from(type : NamedType)
      self.new("::#{type.name}")
    end

    def_equals_and_hash name

    def to_s(io : IO)
      io << name
    end

    def inspect
      to_s
    end
  end

  class IUnion
    getter types : Array(IType)
    getter? can_grow : Bool

    def initialize(*types : IType, @can_grow : Bool)
      @types = types.to_a
    end

    def to_s(io : IO)
      io << "Union#{@can_grow ? "+" : ""}("
      @types.each_with_index do |t, index|
        io << ", " if index > 0
        t.to_s(io)
      end
      io << ")"
    end

    def inspect
      to_s
    end
  end

  class ITypeVariable
    getter id : UInt64

    def initialize(@id)
    end

    def_equals_and_hash id

    ZERO_ORD = '0'.ord

    def to_s(io : IO)
      io << "𝜎"
      id.to_s.each_char do |c|
        io << '\u2080' + (c.ord - ZERO_ORD)
      end
    end

    def inspect
      to_s
    end
  end

  class IFunctionType
    getter arg_types : Array(IType)?
    getter return_type : IType

    def initialize(@arg_types : Array(IType)?, @return_type : IType)
      raise ArgumentError.new "arg_types can't be empty. use nil." if arg_types && arg_types.empty?
    end

    def to_s(io : IO)
      io << "{"
      @arg_types.try(&.each_with_index do |t, index|
        io << ", " if index > 0
        t.to_s(io)
      end)
      io << "} -> " << return_type
    end

    def inspect
      to_s
    end
  end
end
