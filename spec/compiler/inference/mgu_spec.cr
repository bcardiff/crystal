require "../../spec_helper"

private class Types
  def self.foo
    Inference::INamedType.new("::Foo")
  end

  def self.bar
    Inference::INamedType.new("::Bar")
  end

  @@next_var = 0u64

  def self.fresh
    @@next_var += 1u64
    Inference::ITypeVariable.new(@@next_var)
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
end
