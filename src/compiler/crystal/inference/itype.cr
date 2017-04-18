module Crystal::Inference
  alias IType = INamedType | ITypeVariable | IUnion

  class INamedType
    # TODO handle generics
    getter name : String

    def initialize(@name)
    end

    def self.from(type : NamedType)
      self.new("::#{type.name}")
    end

    def_equals_and_hash name
  end

  class IUnion
    getter types : Array(IType)

    def initialize(*types : IType)
      @types = types.to_a
    end
  end

  class ITypeVariable
    getter id : UInt64

    def initialize(@id)
    end

    def_equals_and_hash id
  end
end
