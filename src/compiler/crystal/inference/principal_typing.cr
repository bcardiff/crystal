require "../program"
require "../syntax/ast"
require "../syntax/visitor"
require "../semantic/semantic_visitor"
require "./itype"
require "./constraint"

module Crystal
  class Program
    def infer_types(node : ASTNode)
      visitor = Inference::TypeInferenceVisitor.new(self)
      node.accept(visitor)
      {visitor.last, visitor.context, visitor.constraints}
    end
  end

  module Inference
    class TypeInferenceVisitor < SemanticVisitor
      class NotImplemented < ::Exception
        def initialize(@message)
        end
      end

      getter! last : IType
      getter context = Hash(String, IType).new
      getter constraints = Array(Constraint).new

      def visit(node)
        not_implemented("for #{node.class}")
      end

      # literals

      def visit(node : BoolLiteral)
        @last = INamedType.from(program.bool)
      end

      def visit(node : NumberLiteral)
        @last = INamedType.from(program.type_from_literal_kind(node.kind))
      end

      def visit(node : CharLiteral)
        @last = INamedType.from(program.char)
      end

      def visit(node : BoolLiteral)
        @last = INamedType.from(program.bool)
      end

      def visit(node : NilLiteral)
        @last = INamedType.from(program.nil)
      end

      def visit(node : StringLiteral)
        @last = INamedType.from(program.string)
      end

      def visit(node : SymbolLiteral)
        @last = INamedType.from(program.symbol)
      end

      # variables

      def visit(node : Assign)
        target = node.target
        if target.is_a?(Crystal::Var)
          node.value.accept(self)
          value_type = self.last

          # if the variable is already in the context we must unify with the current type
          # if not we create a new type flexible enough to grow, by been a IUnion(@last, fresh_type).
          # So further unification can use that fresh_type to keep growing.

          t = if current_type = @context[target.name]?
                not_implemented
              else
                IUnion.new(value_type, fresh_type)
              end
          @context[target.name] = @last = t
        else
          not_implemented("for Assign with target #{target.class}")
        end

        false
      end

      def visit(node : Call)
        not_implemented("for Call with receivers") if node.obj
        not_implemented("for Call with block") if node.block
        not_implemented("for Call with named_args") if node.named_args

        if node.args.size > 0
          args_types = [] of IType
          node.args.each do |arg|
            arg.accept(self)
            # TODO mgu over args
            args_types << self.last
          end
        else
          args_types = nil
        end

        @last = return_type = fresh_type

        @constraints << TopLevelMethodConstraint.new(node.name, IFunctionType.new(args_types, return_type))

        false
      end

      private def not_implemented(message = "")
        raise NotImplemented.new("Type inference not implemented #{message}")
      end

      @next_var = 0u64

      private def fresh_type
        @next_var += 1u64
        ITypeVariable.new(@next_var)
      end
    end
  end
end
