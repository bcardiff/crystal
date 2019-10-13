# :nodoc:
struct Crystal::StaticList(T)
  module Node(U)
    @prev = uninitialized Pointer(U)
    @next = uninitialized Pointer(U)

    def prev
      @prev
    end

    def prev=(@prev : Pointer(U))
    end

    def next
      @next
    end

    def next=(@next : Pointer(U))
    end

    def self_pointer
      (->self.itself).closure_data.as(Pointer(U))
    end
  end

  @dummy_head = uninitialized T

  @[AlwaysInline]
  protected def self.link(p : Pointer(T), q : Pointer(T))
    p.value.next = q
    q.value.prev = p
  end

  @[AlwaysInline]
  protected def self.insert_impl(new : Pointer(T), prev : Pointer(T), _next : Pointer(T))
    prev.value.next = new
    new.value.prev = prev
    new.value.next = _next
    _next.value.prev = new
  end

  def init
    @dummy_head.prev = pointerof(@dummy_head)
    @dummy_head.next = pointerof(@dummy_head)
  end

  def list_append_to(list : Pointer(self))
    if !empty?
      typeof(self).link list.value.@dummy_head.prev, @dummy_head.next
      typeof(self).link @dummy_head.prev, list.value.@dummy_head.self_pointer
      init
    end
  end

  def empty?
    @dummy_head.next == pointerof(@dummy_head)
  end

  def push(node : Pointer(T))
    typeof(self).insert_impl node, @dummy_head.prev, pointerof(@dummy_head)
  end

  def delete(node : Pointer(T))
    typeof(self).link node.value.prev, node.value.next
  end

  def shift
    unless empty?
      @dummy_head.next.tap { |t| delete(t) }
    else
      yield
    end
  end

  def shift?
    shift { nil }
  end

  def each
    it = @dummy_head.next
    while it != pointerof(@dummy_head)
      yield it
      it = it.value.next
    end
  end
end
