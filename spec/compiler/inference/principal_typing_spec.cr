require "../../spec_helper"

def type_infered(str)
  program = Program.new
  input = parse str
  input = program.normalize input
  # TODO need to add lexical phases.
  input_type, context = program.infer_types input
  # input_type = input.is_a?(Expressions) ? input.last.type : input.type
  {input_type, context, program}
end

def assert_inferred(str)
  input_type, _, program = type_infered(str)
  helper = TypeHelper.new
  expected_type = with helper yield helper
  input_type.should eq(expected_type)
  input_type
end

def assert_context(str)
  _, context, program = type_infered(str)
  helper = TypeHelper.new
  expected_context = with helper yield helper
  expected_context.each do |key, expected_type|
    raise "not implemented" unless expected_type.is_a?(Inference::INamedType)

    case inferred = context[key.to_s]
    when Inference::INamedType
      inferred.should eq(expected_type)
    when Inference::IUnion
      inferred.types.any? { |t| t == expected_type }.should be_true
    when Inference::ITypeVariable
      expected_type.is_a?(Inference::ITypeVariable).should be_true
    else
      raise "unreachable"
    end
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

  it "assign fresh type to variables" do
    assert_context(%(a = 1)) {
      {a: int32}
    }
  end
end
