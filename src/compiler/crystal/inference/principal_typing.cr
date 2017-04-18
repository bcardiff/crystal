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

      def visit(node : Expressions)
        super
      end

      def visit(node : Assign)
        target = node.target
        if target.is_a?(Crystal::Var)
          node.value.accept(self)
          value_type = self.last

          # if the variable is already in the context we must comply with the current type
          # if not we create a new type flexible enough to grow, by been a IUnion(@last, can_grow: true).
          # TODO: NB that every time a new scope is created the variable context should be inferred, unless fixed
          t = if current_type = @context[target.name]?
                case current_type
                when IUnion
                  if current_type.types.none?(&.==(value_type))
                    if current_type.can_grow?
                      current_type.types << value_type
                    else
                      raise "Compiler error"
                    end
                  else
                    # value_type can be stored. nothing to be done
                  end
                  current_type # TODO CHECK should the assignment return the value_type rather than the variable type?
                else
                  not_implemented
                end
              else
                IUnion.new(value_type, can_grow: true)
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
          arg_types = [] of IType
          node.args.each do |arg|
            arg.accept(self)
            # TODO mgu over args
            arg_types << self.last
          end
        else
          arg_types = nil
        end

        # if there is already a method restriction with the same argument, reuse it
        # and get the return type from it
        @last, _ = build_or_get_method_for_args(node.name, arg_types)

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

      private def build_or_get_method_for_args(name, arg_types)
        existing = @constraints.select { |c|
          c.is_a?(TopLevelMethodConstraint) &&
            c.name == name && c.type.arg_types == arg_types
        }.first?

        if existing
          {existing.type.return_type, existing}
        else
          return_type = fresh_type
          constraint = TopLevelMethodConstraint.new(name, IFunctionType.new(arg_types, return_type))
          @constraints << constraint
          {return_type, constraint}
        end
      end
    end
  end
end
