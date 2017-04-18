require "./itype"

module Crystal::Inference
  struct Substitution
    # @substs == nil means empty substitution
    getter substs : Hash(ITypeVariable, IType)?

    def initialize(@substs = nil)
    end

    def self.empty
      Substitution.new
    end

    def self.none
      nil
    end

    def empty?
      @substs == nil
    end
  end

  def self.mgu(a : IType, b : IType)
    case {a, b}
    when {.is_a?(INamedType), .is_a?(INamedType)}
      a == b ? Substitution.empty : Substitution.none
    when {_, .is_a?(ITypeVariable)}
      Substitution.new({b => a} of ITypeVariable => IType)
    when {.is_a?(ITypeVariable), _}
      Substitution.new({a => b} of ITypeVariable => IType)
    else
      Substitution.none
    end
  end
end
