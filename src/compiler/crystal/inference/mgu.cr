require "./itype"

module Crystal::Inference
  class UnificationException < ::Exception
    def initialize(message)
      super
    end

    def initialize(a : IType, b : IType)
      initialize("Unable to unify #{a} and #{b}")
    end
  end

  struct Substitution
    getter substs : Hash(ITypeVariable, IType)

    def initialize(a : ITypeVariable, b : IType)
      @substs = {a => b} of ITypeVariable => IType
    end

    def initialize(@substs = Hash(ITypeVariable, IType).new)
    end

    def []?(a : ITypeVariable)
      @substs[a]?
    end

    def self.empty
      Substitution.new
    end

    def self.none!(*args)
      raise UnificationException.new(*args)
    end

    def empty?
      @substs.empty?
    end

    def merge!(s : Substitution)
      self.substs.merge!(s.substs)
      self
    end

    def apply(n : Nil)
      nil
    end

    def apply(t : IType)
      t.subst(self)
    end

    def apply(a : Array(IType))
      a.map { |e| apply(e).as(IType) }
    end

    def apply(pair : {IType, IType})
      pair.map { |e| apply(e) }
    end

    def apply(pairs : Array({IType, IType}))
      pairs.map { |e| apply(e) }
    end
  end

  class INamedType
    def subst(s : Substitution)
      self
    end
  end

  class IUnion
    def subst(s : Substitution)
      raise "not implemented"
    end
  end

  class ITypeVariable
    def subst(s : Substitution)
      s[self]? || self
    end
  end

  class IFunctionType
    def subst(s : Substitution)
      self.class.new(s.apply(arg_types), s.apply(return_type))
    end
  end

  def self.mgu(a : IType, b : IType)
    mgu([{a, b}] of {IType, IType})
  end

  def self.mgu(pairs : Array({IType, IType}))
    return Substitution.empty if pairs.empty?

    a, b = pairs.pop

    case {a, b}
    when {.is_a?(INamedType), .is_a?(INamedType)}
      a == b ? mgu(pairs) : Substitution.none!(a, b)
    when {_, .is_a?(ITypeVariable)}
      s = Substitution.new(b, a)
      mgu(s.apply(pairs)).merge!(s)
    when {.is_a?(ITypeVariable), _}
      s = Substitution.new(a, b)
      mgu(s.apply(pairs)).merge!(s)
    when {.is_a?(IFunctionType), .is_a?(IFunctionType)}
      a_args = a.arg_types
      b_args = b.arg_types
      if a_args && b_args
        Substitution.none!("#{a} and #{b} argument count differs") if a_args.size != b_args.size

        a_args.zip(b_args) do |a_arg, b_arg|
          pairs << {a_arg, b_arg}
        end
        pairs << {a.return_type, b.return_type}

        mgu(pairs)
      else
        Substitution.none!("#{a} and #{b} argument count differs") if a_args.nil? != b_args.nil?
        # a_args and b_args are nil
        raise "unify(#{a}, #{b}) not implemented"
      end
    else
      raise "unify(#{a}, #{b}) not implemented"
    end
  end

  def self.mgu?(*args)
    mgu(*args)
  rescue e : UnificationException
    nil
  end
end
