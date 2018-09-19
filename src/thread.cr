require "c/pthread"
require "./thread/*"

# :nodoc:
class Thread
  @@mutex = Thread::Mutex.new

  # Don't use this class, it is used internally by the event scheduler.
  # Use spawn and channels instead.

  @th : LibC::PthreadT?
  @exception : Exception?
  @detached = false
  property! current_fiber : Fiber?

  def initialize(&@func : ->)
    @@mutex.synchronize do
      @@threads << self
      @th = th = uninitialized LibC::PthreadT

      ret = GC.pthread_create(pointerof(th), Pointer(LibC::PthreadAttrT).null, ->(data : Void*) {
        (data.as(Thread)).start
        Pointer(Void).null
      }, self.as(Void*))
      @th = th

      if ret != 0
        raise Errno.new("pthread_create")
      end
    end
  end

  # Used to initialize the crystal object of the
  # existing main thread.
  # Note *the* thread initialized with this constructor
  # will not call `Thread#start`.
  def initialize
    @func = ->{}

    @@mutex.synchronize do
      @@threads << self
      @th = LibC.pthread_self
      @current_fiber = Fiber.new(self)
    end
  end

  def finalize
    GC.pthread_detach(@th.not_nil!) unless @detached
  end

  def join
    GC.pthread_join(@th.not_nil!)
    @detached = true

    if exception = @exception
      raise exception
    end
  end

  # All threads, so the GC can see them (GC doesn't scan thread locals)
  # and we can find the current thread on platforms that don't support
  # thread local storage (eg: OpenBSD)
  @@threads = Set(Thread).new

  @@main = new

  def self.current : Thread
    if main?
      return @@main
    else
      find_current_by_id
    end
  end

  protected def start
    # Initialize main fiber of thread once the thread has started.
    # Before the thread actually starts there is no fiber information
    @current_fiber ||= Fiber.new(self)

    begin
      @func.call
    rescue ex
      @exception = ex
    ensure
      @@threads.delete(self)
    end
  end

  def stack_bottom
    LibC.pthread_get_stackaddr_np(@th.not_nil!)
  end

  def stack_size
    LibC.pthread_get_stacksize_np(@th.not_nil!)
  end

  # Checks if the current thread is the main thread
  def self.main?
    LibC.pthread_main_np == 1
  end

  # Find the current thread object with a linear search among all threads
  protected def self.find_current_by_id : Thread
    @@mutex.synchronize do
      current_thread_id = LibC.pthread_self

      current_thread = @@threads.find do |thread|
        LibC.pthread_equal(thread.id, current_thread_id) != 0
      end

      raise "Error: failed to find current thread" unless current_thread
      current_thread
    end
  end

  protected def id
    @th.not_nil!
  end
end
