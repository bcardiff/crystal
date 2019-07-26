{% unless flag?(:win32) %}
  @[Link("pthread")]
{% end %}

{% if flag?(:freebsd) %}
  @[Link("gc-threaded")]
{% else %}
  @[Link("gc", static: true)]
{% end %}

lib LibGC
  alias Int = LibC::Int
  alias SizeT = LibC::SizeT
  alias Word = LibC::ULong

  fun init = GC_init
  fun malloc = GC_malloc(size : SizeT) : Void*
  fun malloc_atomic = GC_malloc_atomic(size : SizeT) : Void*
  fun realloc = GC_realloc(ptr : Void*, size : SizeT) : Void*
  fun free = GC_free(ptr : Void*)
  fun collect_a_little = GC_collect_a_little : Int
  fun collect = GC_gcollect
  fun add_roots = GC_add_roots(low : Void*, high : Void*)
  fun enable = GC_enable
  fun disable = GC_disable
  fun is_disabled = GC_is_disabled : Int
  fun set_handle_fork = GC_set_handle_fork(value : Int)

  fun base = GC_base(displaced_pointer : Void*) : Void*
  fun is_heap_ptr = GC_is_heap_ptr(pointer : Void*) : Int
  fun general_register_disappearing_link = GC_general_register_disappearing_link(link : Void**, obj : Void*) : Int

  type Finalizer = Void*, Void* ->
  fun register_finalizer = GC_register_finalizer(obj : Void*, fn : Finalizer, cd : Void*, ofn : Finalizer*, ocd : Void**)
  fun register_finalizer_ignore_self = GC_register_finalizer_ignore_self(obj : Void*, fn : Finalizer, cd : Void*, ofn : Finalizer*, ocd : Void**)
  fun invoke_finalizers = GC_invoke_finalizers : Int

  fun get_heap_usage_safe = GC_get_heap_usage_safe(heap_size : Word*, free_bytes : Word*, unmapped_bytes : Word*, bytes_since_gc : Word*, total_bytes : Word*)
  fun set_max_heap_size = GC_set_max_heap_size(Word)

  fun get_start_callback = GC_get_start_callback : Void*
  fun set_start_callback = GC_set_start_callback(callback : ->)

  fun set_push_other_roots = GC_set_push_other_roots(proc : ->)
  fun get_push_other_roots = GC_get_push_other_roots : ->

  fun push_all = GC_push_all(bottom : Void*, top : Void*)
  fun push_all_eager = GC_push_all_eager(bottom : Void*, top : Void*)

  {% if flag?(:preview_mt) %}
    fun set_stackbottom = GC_set_stackbottom(LibC::PthreadT, Void*)
    fun get_stackbottom = GC_get_stackbottom : Void*
  {% else %}
    $stackbottom = GC_stackbottom : Void*
  {% end %}

  fun set_on_collection_event = GC_set_on_collection_event(cb : ->)

  $gc_no = GC_gc_no : LibC::ULong
  $bytes_found = GC_bytes_found : LibC::Long
  # GC_on_collection_event isn't exported.  Can't collect totals without it.
  # bytes_allocd, heap_size, unmapped_bytes are macros

  fun size = GC_size(addr : Void*) : LibC::SizeT

  type FreeList = Void*
  type MsEntry = Void
  type MarkProc = Word*, MsEntry*, MsEntry*, Word -> MsEntry*
  type Kind = LibC::Int

  LOG_MAX_MARK_PROCS = 6
  DS_TAG_BITS        = 2
  DS_PROC            = 2

  fun new_free_list = GC_new_free_list : FreeList*
  fun new_proc = GC_new_proc(MarkProc) : LibC::UInt
  fun new_kind = GC_new_kind(free_list : FreeList*, mark_descriptor_template : Word, add_size_to_descriptor : Int, clear_new_objects : Int) : Kind
  fun generic_malloc = GC_generic_malloc(size : SizeT, kind : Kind) : Void*
  fun get_kind_and_size = GC_get_kind_and_size(obj : Void*, psize : SizeT*) : Kind

  fun set_mark_bit = GC_set_mark_bit(ptr : Void*) : Void*
  fun is_marked = GC_is_marked(ptr : Void*) : Int
  fun mark_and_push = GC_mark_and_push(obj : Void*, msp : MsEntry*, msl : MsEntry*, src : Void**) : MsEntry*

  $least_plausible_heap_addr = GC_least_plausible_heap_addr : Void*
  $greatest_plausible_heap_addr = GC_greatest_plausible_heap_addr : Void*

  type FnType = Void* -> Void*
  fun call_with_alloc_lock = GC_call_with_alloc_lock(fn : FnType, client_data : Void*) : Void*

  {% unless flag?(:win32) %}
    # Boehm GC requires to use GC_pthread_create and GC_pthread_join instead of pthread_create and pthread_join
    fun pthread_create = GC_pthread_create(thread : LibC::PthreadT*, attr : LibC::PthreadAttrT*, start : Void* -> Void*, arg : Void*) : LibC::Int
    fun pthread_join = GC_pthread_join(thread : LibC::PthreadT, value : Void**) : LibC::Int
    fun pthread_detach = GC_pthread_detach(thread : LibC::PthreadT) : LibC::Int
  {% end %}
end

private def maybe_mark_and_push(obj, msp, lim, src)
  # Port of gc_mark.h GC_MARK_AND_PUSH macro
  if obj >= LibGC.least_plausible_heap_addr && obj <= LibGC.greatest_plausible_heap_addr
    LibGC.mark_and_push(obj, msp, lim, src)
  else
    msp
  end
end

module GC
  # :nodoc:
  def self.malloc(size : LibC::SizeT) : Void*
    LibGC.malloc(size)
  end

  # :nodoc:
  def self.malloc_atomic(size : LibC::SizeT) : Void*
    LibGC.malloc_atomic(size)
  end

  # :nodoc:
  def self.realloc(ptr : Void*, size : LibC::SizeT) : Void*
    LibGC.realloc(ptr, size)
  end

  # :nodoc:
  def self.malloc_array(t : T.class) forall T
    # All Array(T) have the same size. Doing malloc_array(MyAbstract.class)
    # lead to instance_sizeof(Array(Object)) if T is used instance_sizeof(Array(T))
    LibGC.generic_malloc(LibC::SizeT.new(instance_sizeof(Array(Int32))), array_kind)
  end

  def self.init
    {% unless flag?(:win32) %}
      LibGC.set_handle_fork(1)
    {% end %}
    LibGC.init

    LibGC.set_start_callback ->do
      GC.lock_write
    end
  end

  def self.collect
    LibGC.collect
  end

  def self.enable
    unless LibGC.is_disabled != 0
      raise "GC is not disabled"
    end

    LibGC.enable
  end

  def self.disable
    LibGC.disable
  end

  def self.free(pointer : Void*)
    LibGC.free(pointer)
  end

  def self.add_finalizer(object : Reference)
    add_finalizer_impl(object)
  end

  def self.add_finalizer(object)
    # Nothing
  end

  private def self.add_finalizer_impl(object : T) forall T
    LibGC.register_finalizer_ignore_self(object.as(Void*),
      ->(obj, data) { obj.as(T).finalize },
      nil, nil, nil)
    nil
  end

  def self.add_root(object : Reference)
    roots = @@roots ||= [] of Pointer(Void)
    roots << Pointer(Void).new(object.object_id)
  end

  def self.register_disappearing_link(pointer : Void**)
    base = LibGC.base(pointer.value)
    LibGC.general_register_disappearing_link(pointer, base)
  end

  def self.is_heap_ptr(pointer : Void*)
    LibGC.is_heap_ptr(pointer) != 0
  end

  @@array_kind : LibGC::Kind?

  # :nodoc:
  private def self.array_kind
    @@array_kind ||= begin
      array_free_list = LibGC.new_free_list
      proc = LibGC.new_proc(->(addr : LibGC::Word*, mark_stack_ptr : LibGC::MsEntry*, mark_stack_limit : LibGC::MsEntry*, env : LibGC::Word) {
        array_addr = addr
        # TODO check if env == 1 (debug allocator) and use array_addr = GC_USR_PTR_FROM_BASE(addr)

        typed_addr = array_addr.as(Pointer({Int32, Int32, Int32, Array::Buffer(UInt8)}))
        size = typed_addr.value[1]
        element_size = typed_addr.value[2]
        buffer = typed_addr.value[3]

        # Prevent the buffer itself of being collected
        # LibGC.set_mark_bit(buffer.as(Void*))
        LibGC.call_with_alloc_lock(->LibGC.set_mark_bit, buffer.as(Void*))

        # Prevent all potential pointers from being collected (manual iterate)
        ptr = buffer.data.as(Void**)
        (size * element_size // sizeof(Void*)).times do |i|
          mark_stack_ptr = maybe_mark_and_push(ptr[i], mark_stack_ptr, mark_stack_limit, Pointer(Pointer(Void)).null)
        end

        # Prevent all potential pointers from being collected (mamem range iterate)
        # first_elem = buffer.data
        # last_elem = buffer.data + (size * element_size)
        # LibGC.push_all(first_elem, last_elem)
        # LibGC.push_all_eager(first_elem, last_elem)

        mark_stack_ptr
      })
      LibGC.new_kind(array_free_list, make_proc(proc, 0), 0, 1)
    end
  end

  private def self.make_proc(proc_index, env)
    (((env << LibGC::LOG_MAX_MARK_PROCS) | proc_index) << LibGC::DS_TAG_BITS) | LibGC::DS_PROC
  end

  def self.stats
    LibGC.get_heap_usage_safe(out heap_size, out free_bytes, out unmapped_bytes, out bytes_since_gc, out total_bytes)
    # collections = LibGC.gc_no - 1
    # bytes_found = LibGC.bytes_found

    Stats.new(
      # collections: collections,
      # bytes_found: bytes_found,
      heap_size: heap_size,
      free_bytes: free_bytes,
      unmapped_bytes: unmapped_bytes,
      bytes_since_gc: bytes_since_gc,
      total_bytes: total_bytes
    )
  end

  {% unless flag?(:win32) %}
    # :nodoc:
    def self.pthread_create(thread : LibC::PthreadT*, attr : LibC::PthreadAttrT*, start : Void* -> Void*, arg : Void*)
      LibGC.pthread_create(thread, attr, start, arg)
    end

    # :nodoc:
    def self.pthread_join(thread : LibC::PthreadT) : Void*
      ret = LibGC.pthread_join(thread, out value)
      raise Errno.new("pthread_join", ret) unless ret == 0
      value
    end

    # :nodoc:
    def self.pthread_detach(thread : LibC::PthreadT)
      LibGC.pthread_detach(thread)
    end
  {% end %}

  # :nodoc:
  def self.current_thread_stack_bottom
    {% if flag?(:preview_mt) %}
      LibGC.get_stackbottom
    {% else %}
      LibGC.stackbottom
    {% end %}
  end

  # :nodoc:
  {% if flag?(:preview_mt) %}
    def self.set_stackbottom(thread : Thread, stack_bottom : Void*)
      LibGC.set_stackbottom(thread.to_unsafe, stack_bottom)
    end
  {% else %}
    def self.set_stackbottom(stack_bottom : Void*)
      LibGC.stackbottom = stack_bottom
    end
  {% end %}

  # :nodoc:
  def self.lock_read
    {% if flag?(:preview_mt) %}
      GC.disable
    {% end %}
  end

  # :nodoc:
  def self.unlock_read
    {% if flag?(:preview_mt) %}
      GC.enable
    {% end %}
  end

  # :nodoc:
  def self.lock_write
  end

  # :nodoc:
  def self.unlock_write
  end

  # :nodoc:
  def self.push_stack(stack_top, stack_bottom)
    LibGC.push_all_eager(stack_top, stack_bottom)
  end

  # :nodoc:
  def self.before_collect(&block)
    @@curr_push_other_roots = block
    @@prev_push_other_roots = LibGC.get_push_other_roots

    LibGC.set_push_other_roots ->do
      @@curr_push_other_roots.try(&.call)
      @@prev_push_other_roots.try(&.call)
    end
  end

  # pushes the stack of pending fibers when the GC wants to collect memory:
  GC.before_collect do
    Fiber.unsafe_each do |fiber|
      fiber.push_gc_roots unless fiber.running?
    end

    {% if flag?(:preview_mt) %}
      Thread.unsafe_each do |thread|
        fiber = thread.scheduler.@current
        GC.set_stackbottom(thread, fiber.@stack_bottom)
      end
    {% end %}

    GC.unlock_write
  end
end
