require "fiber"
require "crystal/spin_lock"
require "crystal/pointer_linked_list"

# A `Channel` enables concurrent communication between fibers.
#
# They allow communicating data between fibers without sharing memory and without having to worry about locks, semaphores or other special structures.
#
# ```
# channel = Channel(Int32).new
#
# spawn do
#   channel.send(0)
#   channel.send(1)
# end
#
# channel.receive # => 0
# channel.receive # => 1
# ```
#
# NOTE: Althought a `Channel(Nil)` or any other nilable types like `Channel(Int32?)` are valid
# they are discouraged since from certain methods or constructs it receiving a `nil` as data
# will be indistinguishable from a closed channel.
#
class Channel(T)
  @lock = Crystal::SpinLock.new
  @queue : Deque(T)?

  record NotReady
  record UseDefault

  module SelectAction(S)
    abstract def execute : DeliveryState
    abstract def wait(context : SelectContext(S))
    abstract def wait_result_impl(context : SelectContext(S))
    abstract def unwait
    abstract def result : S
    abstract def lock_object_id
    abstract def lock
    abstract def unlock

    def create_context_and_wait(state_ptr)
      context = SelectContext.new(state_ptr, self)
      self.wait(context)
      context
    end

    # wait_result overload allow implementors to define
    # wait_result_impl with the right type and Channel.select_impl
    # to allow dispatching over unions that will not happen
    def wait_result(context : SelectContext)
      raise "BUG: Unexpected call to #{typeof(self)}#wait_result(context : #{typeof(context)})"
    end

    def wait_result(context : SelectContext(S))
      wait_result_impl(context)
    end

    # Implementor that returns `Channel::UseDefault` in `#execute`
    # must redefine `#default_result`
    def default_result
      raise "unreachable"
    end
  end

  enum SelectState
    None   = 0
    Active = 1
    Done   = 2
  end

  private class SelectContext(S)
    @state : Pointer(Atomic(SelectState))
    property action : SelectAction(S)
    @activated = false

    def initialize(@state, @action : SelectAction(S))
    end

    def activated?
      @activated
    end

    def try_trigger : Bool
      _, succeed = @state.value.compare_and_set(SelectState::Active, SelectState::Done)
      if succeed
        @activated = true
      end
      succeed
    end
  end

  class ClosedError < Exception
    def initialize(msg = "Channel is closed")
      super(msg)
    end
  end

  enum DeliveryState
    None
    Delivered
    Closed
  end

  # :nodoc:
  struct Sender(T)
    include Crystal::PointerLinkedList::Node

    property fiber : Fiber
    property data : T
    property state : DeliveryState
    property select_context : SelectContext(Nil)?

    def initialize
      @fiber = uninitialized Fiber
      @data = uninitialized T
      @state = DeliveryState::None
    end
  end

  # :nodoc:
  struct Receiver(T)
    include Crystal::PointerLinkedList::Node

    property fiber : Fiber
    property data : T
    property state : DeliveryState
    property select_context : SelectContext(T)?

    def initialize
      @fiber = uninitialized Fiber
      @data = uninitialized T
      @state = DeliveryState::None
    end
  end

  def initialize(@capacity = 0)
    @closed = false

    @senders = Crystal::PointerLinkedList(Sender(T)).new
    @receivers = Crystal::PointerLinkedList(Receiver(T)).new

    if capacity > 0
      @queue = Deque(T).new(capacity)
    end
  end

  def close : Nil
    sender_list = Crystal::PointerLinkedList(Sender(T)).new
    receiver_list = Crystal::PointerLinkedList(Receiver(T)).new

    @lock.sync do
      @closed = true

      @senders.append_to sender_list
      @receivers.append_to receiver_list
    end

    sender_list.each do |sender_ptr|
      sender_ptr.value.state = DeliveryState::Closed
      select_context = sender_ptr.value.select_context
      if select_context.nil? || select_context.try_trigger
        sender_ptr.value.fiber.enqueue
      end
    end

    receiver_list.each do |receiver_ptr|
      receiver_ptr.value.state = DeliveryState::Closed
      select_context = receiver_ptr.value.select_context
      if select_context.nil? || select_context.try_trigger
        receiver_ptr.value.fiber.enqueue
      end
    end
  end

  def closed?
    @closed
  end

  def send(value : T)
    sender = Sender(T).new

    @lock.lock

    case send_internal(value)
    when DeliveryState::Delivered
      @lock.unlock
    when DeliveryState::Closed
      @lock.unlock
      raise ClosedError.new
    else
      sender.fiber = Fiber.current
      sender.data = value
      @senders.push pointerof(sender)
      @lock.unlock

      Crystal::Scheduler.reschedule

      case sender.state
      when DeliveryState::Delivered
        # ignore
      when DeliveryState::Closed
        raise ClosedError.new
      else
        raise "BUG: Fiber was awaken without channel delivery state set"
      end
    end

    self
  end

  protected def send_internal(value : T)
    if @closed
      DeliveryState::Closed
    elsif receiver_ptr = dequeue_receiver
      receiver_ptr.value.data = value
      receiver_ptr.value.state = DeliveryState::Delivered
      receiver_ptr.value.fiber.enqueue

      DeliveryState::Delivered
    elsif (queue = @queue) && queue.size < @capacity
      queue << value

      DeliveryState::Delivered
    else
      DeliveryState::None
    end
  end

  # Receives a value from the channel.
  # If there is a value waiting, it is returned immediately. Otherwise, this method blocks until a value is sent to the channel.
  #
  # Raises `ClosedError` if the channel is closed or closes while waiting for receive.
  #
  # ```
  # channel = Channel(Int32).new
  # channel.send(1)
  # channel.receive # => 1
  # ```
  def receive
    receive_impl { raise ClosedError.new }
  end

  # Receives a value from the channel.
  # If there is a value waiting, it is returned immediately. Otherwise, this method blocks until a value is sent to the channel.
  #
  # Returns `nil` if the channel is closed or closes while waiting for receive.
  def receive?
    receive_impl { return nil }
  end

  def receive_impl
    receiver = Receiver(T).new

    @lock.lock

    state, value = receive_internal

    case state
    when DeliveryState::Delivered
      @lock.unlock
      raise "BUG: Unexpected UseDefault value for delivered receive" if value.is_a?(UseDefault)
      value
    when DeliveryState::Closed
      @lock.unlock
      yield
    else
      receiver.fiber = Fiber.current
      @receivers.push pointerof(receiver)
      @lock.unlock

      Crystal::Scheduler.reschedule

      case receiver.state
      when DeliveryState::Delivered
        receiver.data
      when DeliveryState::Closed
        yield
      else
        raise "BUG: Fiber was awaken without channel delivery state set"
      end
    end
  end

  def receive_internal
    if (queue = @queue) && !queue.empty?
      deque_value = queue.shift
      if sender_ptr = dequeue_sender
        queue << sender_ptr.value.data
        sender_ptr.value.state = DeliveryState::Delivered
        sender_ptr.value.fiber.enqueue
      end

      {DeliveryState::Delivered, deque_value}
    elsif sender_ptr = dequeue_sender
      value = sender_ptr.value.data
      sender_ptr.value.state = DeliveryState::Delivered
      sender_ptr.value.fiber.enqueue

      {DeliveryState::Delivered, value}
    elsif @closed
      {DeliveryState::Closed, UseDefault.new}
    else
      {DeliveryState::None, UseDefault.new}
    end
  end

  private def dequeue_receiver
    while receiver_ptr = @receivers.shift?
      select_context = receiver_ptr.value.select_context
      if select_context && !select_context.try_trigger
        receiver_ptr.value.state = DeliveryState::Delivered
        next
      end

      break
    end

    receiver_ptr
  end

  private def dequeue_sender
    while sender_ptr = @senders.shift?
      select_context = sender_ptr.value.select_context
      if select_context && !select_context.try_trigger
        sender_ptr.value.state = DeliveryState::Delivered
        next
      end

      break
    end

    sender_ptr
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  def pretty_print(pp)
    pp.text inspect
  end

  def self.receive_first(*channels)
    receive_first channels
  end

  def self.receive_first(channels : Tuple | Array)
    _, value = self.select(channels.map(&.receive_select_action))
    value
  end

  def self.send_first(value, *channels)
    send_first value, channels
  end

  def self.send_first(value, channels : Tuple | Array)
    self.select(channels.map(&.send_select_action(value)))
    nil
  end

  def self.select(*ops : SelectAction)
    self.select ops
  end

  def self.select(ops : Indexable(SelectAction))
    i, m = select_impl(ops, false)
    raise "BUG: blocking select returned not ready status" if m.is_a?(NotReady)
    return i, m
  end

  @[Deprecated("Use Channel.non_blocking_select")]
  def self.select(ops : Indexable(SelectAction), has_else)
    # The overload of Channel.select(Indexable(SelectAction), Bool)
    # is used by LiteralExpander with the second argument as `true`.
    # This overload is kept as a transition, but 0.32 will emit calls to
    # Channel.select or Channel.non_blocking_select directly
    non_blocking_select(ops)
  end

  def self.non_blocking_select(*ops : SelectAction)
    self.non_blocking_select ops
  end

  def self.non_blocking_select(ops : Indexable(SelectAction))
    select_impl(ops, true)
  end

  def self.select_impl(ops : Indexable(SelectAction), non_blocking)
    # Sort the operations by the channel they contain
    # This is to avoid deadlocks between concurrent `select` calls
    ops_locks = ops
      .to_a
      .uniq(&.lock_object_id)
      .sort_by(&.lock_object_id)

    ops_locks.each &.lock

    ops.each_with_index do |op, index|
      state = op.execute

      case state
      when DeliveryState::Delivered
        ops_locks.each &.unlock
        return index, op.result
      when DeliveryState::Closed
        ops_locks.each &.unlock
        return index, op.default_result
      else
        # do nothing
      end
    end

    if non_blocking
      ops_locks.each &.unlock
      return ops.size, NotReady.new
    end

    # Because channel#close may clean up a long list, `select_context.try_trigger` may
    # be called after the select return. In order to prevent invalid address access,
    # the state is allocated in the heap.
    state_ptr = Pointer.malloc(1, Atomic(SelectState).new(SelectState::Active))
    contexts = ops.map &.create_context_and_wait(state_ptr)

    ops_locks.each &.unlock
    Crystal::Scheduler.reschedule

    ops.each do |op|
      op.lock
      op.unwait
      op.unlock
    end

    contexts.each_with_index do |context, index|
      if context.activated?
        return index, ops[index].wait_result(context)
      end
    end

    raise "BUG: Fiber was awaken from select but no action was activated"
  end

  # :nodoc:
  def send_select_action(value : T)
    SendAction.new(self, value)
  end

  # :nodoc:
  def receive_select_action
    StrictReceiveAction.new(self)
  end

  # :nodoc:
  def receive_select_action?
    LooseReceiveAction.new(self)
  end

  # :nodoc:
  class StrictReceiveAction(T)
    include SelectAction(T)
    property receiver : Receiver(T)

    def initialize(@channel : Channel(T))
      @receiver = Receiver(T).new
    end

    def execute : DeliveryState
      state, value = @channel.receive_internal

      if state.delivered?
        @receiver.data = value.as(T)
      end

      state
    end

    def result : T
      @receiver.data
    end

    def wait(context : SelectContext(T))
      @receiver.fiber = Fiber.current
      @receiver.select_context = context
      @channel.@receivers.push pointerof(@receiver)
    end

    def wait_result_impl(context : SelectContext(T))
      case @receiver.state
      when DeliveryState::Delivered
        context.action.result
      when DeliveryState::Closed
        raise ClosedError.new
      when DeliveryState::None
        raise "BUG: StrictReceiveAction.wait_result_impl called with DeliveryState::None"
      else
        raise "unreachable"
      end
    end

    def unwait
      if !@channel.closed? && @receiver.state.none?
        @channel.@receivers.delete pointerof(@receiver)
      end
    end

    def lock_object_id
      @channel.object_id
    end

    def lock
      @channel.@lock.lock
    end

    def unlock
      @channel.@lock.unlock
    end

    def default_result
      raise ClosedError.new
    end
  end

  # :nodoc:
  class LooseReceiveAction(T)
    include SelectAction(T)
    property receiver : Receiver(T)

    def initialize(@channel : Channel(T))
      @receiver = Receiver(T).new
    end

    def execute : DeliveryState
      state, value = @channel.receive_internal

      if state.delivered?
        @receiver.data = value.as(T)
      end

      state
    end

    def result : T
      @receiver.data
    end

    def wait(context : SelectContext(T))
      @receiver.fiber = Fiber.current
      @receiver.select_context = context
      @channel.@receivers.push pointerof(@receiver)
    end

    def wait_result_impl(context : SelectContext(T))
      case @receiver.state
      when DeliveryState::Delivered
        context.action.result
      when DeliveryState::Closed
        nil
      when DeliveryState::None
        raise "BUG: LooseReceiveAction.wait_result_impl called with DeliveryState::None"
      else
        raise "unreachable"
      end
    end

    def unwait
      if !@channel.closed? && @receiver.state.none?
        @channel.@receivers.delete pointerof(@receiver)
      end
    end

    def lock_object_id
      @channel.object_id
    end

    def lock
      @channel.@lock.lock
    end

    def unlock
      @channel.@lock.unlock
    end

    def default_result
      nil
    end
  end

  # :nodoc:
  class SendAction(T)
    include SelectAction(Nil)
    property sender : Sender(T)

    def initialize(@channel : Channel(T), value : T)
      @sender = Sender(T).new
      @sender.data = value
    end

    def execute : DeliveryState
      @channel.send_internal(@sender.data)
    end

    def result : Nil
      nil
    end

    def wait(context : SelectContext(Nil))
      @sender.fiber = Fiber.current
      @sender.select_context = context
      @channel.@senders.push pointerof(@sender)
    end

    def wait_result_impl(context : SelectContext(Nil))
      case @sender.state
      when DeliveryState::Delivered
        context.action.result
      when DeliveryState::Closed
        raise ClosedError.new
      when DeliveryState::None
        raise "BUG: SendAction.wait_result_impl called with DeliveryState::None"
      else
        raise "unreachable"
      end
    end

    def unwait
      if !@channel.closed? && @sender.state.none?
        @channel.@senders.delete pointerof(@sender)
      end
    end

    def lock_object_id
      @channel.object_id
    end

    def lock
      @channel.@lock.lock
    end

    def unlock
      @channel.@lock.unlock
    end

    def default_result
      raise ClosedError.new
    end
  end
end
