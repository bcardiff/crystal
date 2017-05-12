require "./itype"

module Crystal::Inference
  abstract struct Constraint
  end

  struct TopLevelMethodConstraint < Constraint
    getter name : String
    getter type : IFunctionType

    def initialize(@name : String, @type : IFunctionType)
    end

    def to_s(io : IO)
      io << "#{name} : #{type}"
    end
  end
end
