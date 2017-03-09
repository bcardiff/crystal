require "set"
require "../program"
require "../syntax/transformer"

module Crystal
  class SimpleRescues < Transformer
    @i = 0

    def transform(node : ExceptionHandler)
      rescues = node.rescues

      if rescues
        if rescues.size > 1
          var_name = next_var
          ensure_body = Call.global("raise", Var.new(var_name))

          rescues.reverse_each do |rescue_node|
            typed_var_name, restriction_type, body = split_ensure rescue_node
            if restriction_type
              ensure_body = type_restricted_ensure_body(var_name,
                typed_var_name, restriction_type, body.transform(self), ensure_body)
            else
              ensure_body = Expressions.from [
                Assign.new(Var.new(typed_var_name), Var.new(var_name)),
                body,
              ]
            end
          end
        else
          typed_var_name, restriction_type, body = split_ensure rescues.first
          var_name = typed_var_name
          if restriction_type
            ensure_body = If.new(
              IsA.new(Var.new(typed_var_name), restriction_type),
              body, Call.global("raise", Var.new(var_name)))
          else
            ensure_body = body
          end
        end

        node.rescues = [Rescue.new(ensure_body, nil, var_name)]
      end

      node
    end

    private def split_ensure(node : Rescue)
      types = node.types

      if types
        restriction_type = types.size == 1 ? types[0] : Union.new(types)
      else
        restriction_type = nil
      end

      {node.name || next_var, restriction_type, node.body}
    end

    private def type_restricted_ensure_body(var_name : String,
                                            typed_var_name : String, restriction_type : ASTNode,
                                            body : ASTNode, cont : ASTNode)
      If.new(
        And.new(Assign.new(Var.new(typed_var_name), Var.new(var_name)),
          IsA.new(Var.new(typed_var_name), restriction_type)),
        body, cont)
    end

    private def next_var
      @i += 1
      "___e#{@i}"
    end
  end
end
