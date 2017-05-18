require "./inference_spec"

private alias T = ::Crystal::Inference::TypeHelper

private def mgu(*args)
  Inference.mgu(*args)
end

describe "mgu" do
  it "returns empty substitution on equal INamedType" do
    s = mgu(T.foo, T.foo).not_nil!
    s.empty?.should be_true
  end

  it "returns no substitution on distinct INamedType" do
    mgu(T.foo, T.bar).should be_nil
  end

  it "returns simple substitution between INamedType and ITypeVariable" do
    s = mgu(T.foo, t1 = T.fresh).not_nil!
    s.substs.should eq({t1 => T.foo})
  end

  it "returns simple substitution between ITypeVariable and INamedType" do
    s = mgu(t1 = T.fresh, T.foo).not_nil!
    s.substs.should eq({t1 => T.foo})
  end

  it "returns simple substitution between ITypeVariable" do
    s = mgu(t1 = T.fresh, t2 = T.fresh).not_nil!
    s.substs.should eq({t2 => t1})
  end

  it "returns simple substitution between IFunctionType and ITypeVariable" do
    s = mgu(f1 = T.func(T.foo, T.bar), t1 = T.fresh).not_nil!
    s.substs.should eq({t1 => f1})
  end

  it "returns simple substitution between ITypeVariable and IFunctionType" do
    s = mgu(t1 = T.fresh, f1 = T.func(T.foo, T.bar)).not_nil!
    s.substs.should eq({t1 => f1})
  end

  it "deconstruct IFunctionType and match inner arguments" do
    s = mgu(T.func(T.foo, T.bar), T.func(T.foo, T.bar)).not_nil!
    s.empty?.should be_true

    mgu(T.func(T.foo, T.bar), T.func(T.foo, T.foo)).should be_nil

    s = mgu(T.func(t1 = T.fresh, T.bar), T.func(T.foo, t2 = T.fresh)).not_nil!
    s.substs.should eq({t1 => T.foo, t2 => T.bar})
  end
end
