require "./itype"

module Crystal::Inference
  abstract struct Constraint
  end

  struct TopLevelMethodConstraint < Constraint
    getter name : String
    getter type : IFunctionType

    def initialize(@name : String, @type : IFunctionType)
    end
  end
end
