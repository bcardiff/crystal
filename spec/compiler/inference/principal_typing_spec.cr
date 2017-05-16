require "../../spec_helper"

def type_infered(str)
  program = Program.new
  input = parse str
  input = program.normalize input
  # TODO need to add lexical phases.
  input_type, context, constraints, idefs = program.infer_types input
  # input_type = input.is_a?(Expressions) ? input.last.type : input.type
  {input_type, context, constraints, idefs, program}
end

def assert_inferred(str)
  input_type, _, _, _, program = type_infered(str)
  helper = TypeHelper.new
  expected_type = with helper yield helper
  input_type.should eq(expected_type)
  input_type
end

def assert_inference(str)
  _, context, constraints, idefs, program = type_infered(str)
  helper = TypeHelper.new
  expected_context = with helper yield helper, context, constraints, idefs
end

private def assert_match(idef : Inference::IDef, expected_type : Inference::IFunctionType)
  subst = Inference.mgu(idef.type, expected_type)
  return if subst
  fail("mgu(#{idef.type}, #{expected_type}) failed")
end

def assert_can_store(inferred_type, expected_type)
  raise "not implemented" unless expected_type.is_a?(Inference::INamedType) || expected_type.is_a?(Inference::ITypeVariable)

  case expected_type
  when Inference::ITypeVariable
    case inferred_type
    when Inference::INamedType
      fail("#{expected_type} can't be stored in #{inferred_type}")
    when Inference::IUnion
      inferred_type.types.any? { |t| t == expected_type }.should be_true
    when Inference::ITypeVariable
      inferred_type.should eq(expected_type)
    else
      fail("case not handled assert_can_store(#{inferred_type}, #{expected_type})")
    end
  when Inference::INamedType
    case inferred_type
    when Inference::INamedType
      inferred_type.should eq(expected_type)
    when Inference::IUnion
      inferred_type.types.any? { |t| t == expected_type }.should be_true
    when Inference::ITypeVariable
      expected_type.is_a?(Inference::ITypeVariable).should be_true
    else
      fail("case not handled assert_can_store(#{inferred_type}, #{expected_type})")
    end
  else
    fail("case not handled assert_can_store(#{inferred_type}, #{expected_type})")
  end
end

private class TypeHelper
  def bool
    Inference::INamedType.new("::Bool")
  end

  def int32
    Inference::INamedType.new("::Int32")
  end

  def int64
    Inference::INamedType.new("::Int64")
  end

  def char
    Inference::INamedType.new("::Char")
  end

  def nil
    Inference::INamedType.new("::Nil")
  end

  def string
    Inference::INamedType.new("::String")
  end

  def symbol
    Inference::INamedType.new("::Symbol")
  end
end

describe "principal typing" do
  it "infer literals" do
    assert_inferred("false") { bool }
    assert_inferred("1") { int32 }
    assert_inferred("1i64") { int64 }
    assert_inferred("'a'") { char }
    assert_inferred("nil") { |p| p.nil }
    assert_inferred(%("a")) { string }
    assert_inferred(%(:a)) { symbol }
  end

  it "variable type can hold assigned value" do
    assert_inference(%(a = 1)) do |h, context, _|
      assert_can_store(context["a"], h.int32)
    end
  end

  it "expressions are iterated" do
    assert_inference(%(a = 1; b = 'c')) do |h, context, _|
      assert_can_store(context["a"], int32)
      assert_can_store(context["b"], char)
    end
  end

  it "variables can hold all the required values" do
    assert_inference(%(a = 1; a = 'c')) do |h, context, _|
      assert_can_store(context["a"], int32)
      assert_can_store(context["a"], char)
    end
  end

  it "a top level def call creates a TopLevelMethodConstraint" do
    assert_inference(%(a = method(1))) do |h, context, constraints|
      # where
      # - method : {int32} -> 𝜎₁
      method = constraints.first
      method.should be_a(Inference::TopLevelMethodConstraint)
      method.name.should eq("method")
      method.type.arg_types.should eq([int32])
      assert_can_store(context["a"], method.type.return_type)
    end
  end

  it "same method overloads constraints are reused" do
    assert_inference(%(a = method(m2, m2))) do |h, context, constraints|
      # where
      # - m2 : {} -> 𝜎₁
      # - method : {𝜎₁, 𝜎₁} -> 𝜎₂
      constraints.size.should eq(2)
      m2 = constraints.select(&.name.==("m2")).first
      m2.should be_a(Inference::TopLevelMethodConstraint)

      method = constraints.select(&.name.==("method")).first
      method.should be_a(Inference::TopLevelMethodConstraint)
      method.type.arg_types.should eq([m2.type.return_type, m2.type.return_type])

      assert_can_store(context["a"], method.type.return_type)
    end
  end

  it "different method overloads creates different TopLevelMethodConstraint" do
    assert_inference(%(method(1); method('c'))) do |h, context, constraints|
      # where
      # - method : {int32} -> 𝜎₁
      # - method : {char} -> 𝜎₂
      constraints.size.should eq(2)

      m_int = constraints[0]
      m_int.type.arg_types.should eq([int32])

      m_char = constraints[1]
      m_char.type.arg_types.should eq([char])
    end
  end

  it "collects defs with independent inference" do
    assert_inference(%(
    def foo
      qux
    end

    def bar
      qux
    end
    )) do |h, context, constraints, idefs|
      # foo : {} -> 𝜎₁
      #   where
      #   - qux : {} -> 𝜎₁
      d_foo = idefs[0]
      d_foo.def.name == "foo"
      qux_1 = d_foo.constraints[0]
      d_foo.type.arg_types.should be_nil
      qux_1.type.return_type.should eq(d_foo.type.return_type)

      # bar : {} -> 𝜎₂
      #   where
      #   - qux : {} -> 𝜎₂
      d_bar = idefs[1]
      d_bar.def.name == "bar"
      qux_2 = d_bar.constraints[0]
      d_bar.type.arg_types.should be_nil
      qux_2.type.return_type.should eq(d_bar.type.return_type)

      d_foo.type.return_type.should_not eq(d_bar.type.return_type)
    end
  end

  it "assigns type variable to arguments" do
    assert_inference(%(
    def foo(a)
      a
    end
    )) do |h, context, constraints, idefs|
      d_foo = idefs[0]

      t = Inference::ITypeVariable.fresh.as(Inference::IType)
      assert_match(d_foo, Inference::IFunctionType.new([t], t))
    end
  end
end
