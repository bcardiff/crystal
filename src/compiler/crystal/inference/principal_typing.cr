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
      {visitor.last, visitor.context, visitor.constraints, visitor.idefs}
    end
  end

  module Inference
    record IDef, def : Def, type : IFunctionType, constraints : Array(Constraint)

    class TypeInferenceVisitor < SemanticVisitor
      class NotImplemented < ::Exception
        def initialize(@message)
        end
      end

      getter! last : IType
      getter context = Hash(String, IType).new
      getter constraints = Array(Constraint).new
      getter idefs = Array(IDef).new

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

      def visit(node : Def)
        old_context = @context
        old_constraints = @constraints

        @context = Hash(String, IType).new
        @constraints = Array(Constraint).new

        not_implemented("free_vars") if node.free_vars
        not_implemented("receiver") if node.receiver
        not_implemented("double_splat") if node.double_splat
        not_implemented("block_arg") if node.block_arg
        not_implemented("yields") if node.yields
        not_implemented("splat_index") if node.splat_index

        # TODO IFunctionType need to know about names / external names, splats and blocks
        arg_types = nil
        node.args.each do |arg|
          not_implemented("args with default_value") if arg.default_value
          not_implemented("args with restriction") if arg.restriction

          arg_types ||= Array(IType).new(node.args.size)
          arg_type = fresh_type
          @context[arg.name] = arg_type
          arg_types << arg_type
        end

        # TODO use return type annotation
        node.body.accept(self)
        # TODO keep context
        @idefs << IDef.new(node, IFunctionType.new(arg_types, self.last), @constraints)

        @last = INamedType.from(program.nil)
        @context = old_context
        @constraints = old_constraints

        false
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

      def visit(node : Var)
        @last = @context[node.name]
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
