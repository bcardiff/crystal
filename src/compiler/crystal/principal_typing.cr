require "./program"
require "./syntax/ast"
require "./syntax/visitor"
require "./semantic/semantic_visitor"
require "./semantic/type_merge"

class Crystal::Program
  def infer_types(node : ASTNode)
    visitor = TypeInferenceVisitor.new(self)
    node.accept(visitor)
    {visitor.last, visitor.context}
  end

  alias InferredType = Type | TypeVariable

  class TypeVariable
    getter program : Program
    getter id : UInt64
    getter types : Array(Type)?

    def initialize(@program, @id)
    end

    def to_s(io : IO)
      io << ""
    end

    def merge(t : Type)
      types = @types ||= Array(Type).new
      types << t
    end

    def finalized_type
      program.type_merge(types.not_nil!)
    end
  end

  class TypeInferenceVisitor < SemanticVisitor
    class NotImplemented < ::Exception
      def initialize(@message)
      end
    end

    getter! last : InferredType
    getter context = Hash(String, InferredType).new

    def visit(node)
      not_implemented("for #{node.class}")
    end

    # literals

    def visit(node : BoolLiteral)
      @last = program.bool
    end

    def visit(node : NumberLiteral)
      @last = program.type_from_literal_kind node.kind
    end

    def visit(node : CharLiteral)
      @last = program.char
    end

    def visit(node : BoolLiteral)
      @last = program.bool
    end

    def visit(node : NilLiteral)
      @last = program.nil
    end

    def visit(node : StringLiteral)
      @last = program.string
    end

    def visit(node : SymbolLiteral)
      @last = program.symbol
    end

    # variables

    def visit(node : Assign)
      target = node.target
      if target.is_a?(Crystal::Var)
        node.value.accept(self)
        last = @last

        t = TypeVariable.new(program, 1u64) # TODO unique
        not_implemented unless last.is_a?(Type)
        t.merge(last)
        @context[target.name] = t
        @last = t
      else
        not_implemented("for Assign with target #{target.class}")
      end

      false
    end

    # def visit(node : Call)
    #   pp node
    # end

    private def not_implemented(message = "")
      raise NotImplemented.new("Type inference not implemented #{message}")
    end
  end
end
