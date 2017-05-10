require "../../spec_helper"

def type_infered(str)
  program = Program.new
  input = parse str
  input = program.normalize input
  # TODO need to add lexical phases.
  input_type, context, constraints = program.infer_types input
  # input_type = input.is_a?(Expressions) ? input.last.type : input.type
  {input_type, context, constraints, program}
end

def assert_inferred(str)
  input_type, _, _, program = type_infered(str)
  helper = TypeHelper.new
  expected_type = with helper yield helper
  input_type.should eq(expected_type)
  input_type
end

def assert_inference(str)
  _, context, constraints, program = type_infered(str)
  helper = TypeHelper.new
  expected_context = with helper yield helper, context, constraints
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

  it "a top level def call creates a TopLevelMethodConstraint" do
    assert_inference(%(a = method(1))) do |h, context, constraints|
      method = constraints.first
      method.should be_a(Inference::TopLevelMethodConstraint)
      method.name.should eq("method")
      method.type.arg_types.should eq([int32])
      assert_can_store(context["a"], method.type.return_type)
    end
  end
end
