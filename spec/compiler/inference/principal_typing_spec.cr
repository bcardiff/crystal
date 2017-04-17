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
  expected_type = with program yield program
  input_type.should eq(expected_type)
  input_type
end

def assert_context(str)
  _, context, program = type_infered(str)
  expected_context = with program yield program
  expected_context.each do |key, expected_type|
    case inferred = context[key.to_s]
    when Type
      inferred.should eq(expected_type)
    when Program::TypeVariable
      inferred.finalized_type.should eq(expected_type)
    else
      raise "unreachable"
    end
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
