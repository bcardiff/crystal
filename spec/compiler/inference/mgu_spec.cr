require "../../spec_helper"

private class Types
  def self.foo
    Inference::INamedType.new("::Foo")
  end

  def self.bar
    Inference::INamedType.new("::Bar")
  end

  def self.fresh
    Inference::ITypeVariable.fresh
  end

  def self.func(arg : Inference::IType, ret)
    Inference::IFunctionType.new([arg] of Inference::IType, ret)
  end
end

describe "mgu" do
  it "returns empty substitution on equal INamedType" do
    s = Inference.mgu(Types.foo, Types.foo).not_nil!
    s.empty?.should be_true
  end

  it "returns no substitution on distinct INamedType" do
    Inference.mgu(Types.foo, Types.bar).should be_nil
  end

  it "returns simple substitution between INamedType and ITypeVariable" do
    s = Inference.mgu(Types.foo, t1 = Types.fresh).not_nil!
    s.substs.should eq({t1 => Types.foo})
  end

  it "returns simple substitution between ITypeVariable and INamedType" do
    s = Inference.mgu(t1 = Types.fresh, Types.foo).not_nil!
    s.substs.should eq({t1 => Types.foo})
  end

  it "returns simple substitution between ITypeVariable" do
    s = Inference.mgu(t1 = Types.fresh, t2 = Types.fresh).not_nil!
    s.substs.should eq({t2 => t1})
  end

  it "returns simple substitution between IFunctionType and ITypeVariable" do
    s = Inference.mgu(f1 = Types.func(Types.foo, Types.bar), t1 = Types.fresh).not_nil!
    s.substs.should eq({t1 => f1})
  end

  it "returns simple substitution between ITypeVariable and IFunctionType" do
    s = Inference.mgu(t1 = Types.fresh, f1 = Types.func(Types.foo, Types.bar)).not_nil!
    s.substs.should eq({t1 => f1})
  end

  it "deconstruct IFunctionType and match inner arguments" do
    s = Inference.mgu(Types.func(Types.foo, Types.bar), Types.func(Types.foo, Types.bar)).not_nil!
    s.empty?.should be_true

    Inference.mgu(Types.func(Types.foo, Types.bar), Types.func(Types.foo, Types.foo)).should be_nil

    s = Inference.mgu(Types.func(t1 = Types.fresh, Types.bar), Types.func(Types.foo, t2 = Types.fresh)).not_nil!
    s.substs.should eq({t1 => Types.foo, t2 => Types.bar})
  end
end
