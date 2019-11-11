# :nodoc:
#
# Doubly linked list of `T` structs referenced as pointers.
# `T` that must include `Crystal::PointerLinkedList::Node`.
class Crystal::PointerLinkedList(T)
  protected property head : Pointer(T) = Pointer(T).null
  protected property tail : Pointer(T) = Pointer(T).null

  module Node
    macro included
      property previous : Pointer({{@type}}) = Pointer({{@type}}).null
      property next : Pointer({{@type}}) = Pointer({{@type}}).null
    end
  end

  # Iterates the list.
  def each : Nil
    node = @head

    while !node.null?
      yield node
      node = node.value.next
    end
  end

  # Appends a node to the tail of the list.
  def push(node : Pointer(T)) : Nil
    node.value.previous = Pointer(T).null

    if (tail = @tail) && !tail.null?
      node.value.previous = tail
      @tail = tail.value.next = node
    else
      @head = @tail = node
    end
  end

  # Removes a node from the list.
  def delete(node : Pointer(T)) : Nil
    if (previous = node.value.previous) && !previous.null?
      previous.value.next = node.value.next
    else
      @head = node.value.next
    end

    if (_next = node.value.next) && !_next.null?
      _next.value.previous = node.value.previous
    else
      @tail = node.value.previous
    end
  end

  # Removes and returns head from the list, yields if empty
  def shift
    if head = @head
      delete(head)
      head
    else
      yield
    end
  end

  # Returns and returns head from the list, `nil` if empty.
  def shift?
    shift { nil }
  end

  # Moves all the nodes from *self* and appends them to *target*
  def append_to(target : self)
    if (tail = target.tail) && !tail.null?
      tail.value.next = @head
      @head.value.previous = tail
      target.tail = @head
    else
      target.head = @head
      target.tail = @tail
    end

    @head = Pointer(T).null
    @tail = Pointer(T).null
  end
end
