# An `Array` is an ordered, integer-indexed collection of objects of type T.
#
# Array indexing starts at 0. A negative index is assumed to be
# relative to the end of the array: -1 indicates the last element,
# -2 is the next to last element, and so on.
#
# An `Array` can be created using the usual `new` method (several are provided), or with an array literal:
#
# ```
# Array(Int32).new  # => []
# [1, 2, 3]         # Array(Int32)
# [1, "hello", 'x'] # Array(Int32 | String | Char)
# ```
#
# An `Array` can have mixed types, meaning T will be a union of types, but these are determined
# when the array is created, either by specifying T or by using an array literal. In the latter
# case, T will be set to the union of the array literal elements' types.
#
# When creating an empty array you must always specify T:
#
# ```
# [] of Int32 # same as Array(Int32)
# []          # syntax error
# ```
#
# An `Array` is implemented using an internal buffer of some capacity
# and is reallocated when elements are pushed to it when more capacity
# is needed. This is normally known as a [dynamic array](http://en.wikipedia.org/wiki/Dynamic_array).
#
# You can use a special array literal syntax with other types too, as long as they define an argless
# `new` method and a `<<` method. `Set` is one such type:
#
# ```
# set = Set{1, 2, 3} # => Set{1, 2, 3}
# set.class          # => Set(Int32)
# ```
#
# The above is the same as this:
#
# ```
# set = Set(typeof(1, 2, 3)).new
# set << 1
# set << 2
# set << 3
# ```
class Array(T)
  # :nodoc:
  class Buffer(U)
    getter capacity : Int32

    protected def initialize(@capacity)
    end

    def self.allocation_size(capacity)
      raise ArgumentError.new("Negative capacity: #{capacity}") if capacity < 0
      sizeof(Buffer(U)).to_u32 + capacity.to_u32 * sizeof(U)
    end

    def self.new(capacity : Int)
      buffer = GC.malloc(allocation_size(capacity)).as(Buffer(U))
      set_crystal_type_id(buffer)
      buffer.initialize(capacity.to_i32)
      GC.add_finalizer(buffer) if buffer.responds_to?(:finalize)
      buffer
    end

    # Returns a buffer that can hold at least *capacity* elements.
    # May return self if capacity is enough.
    def realloc(capacity)
      buffer = Buffer(U).new(capacity)
      self.data.copy_to(buffer.data, self.capacity) if self.capacity > 0
      buffer
    end

    # Returns a buffer that can hold at least *required_capacity* elements.
    # The actual capacity is guaranteed to be a power of 2.
    # May return self if capacity is enough.
    def ensure_capacity(required_capacity)
      if required_capacity > @capacity
        self.realloc(Math.pw2ceil(required_capacity))
      else
        self
      end
    end

    def double_capacity
      realloc(@capacity == 0 ? 3 : (@capacity * 2))
    end

    @[AlwaysInline]
    def data : U*
      Pointer(U).new(object_id + sizeof(Buffer(U)))
    end
  end

  # :nodoc:
  struct Snapshot(U)
    getter size : Int32
    getter buffer : Buffer(U)
    getter data : U*

    include Indexable(U)

    def initialize(@size : Int32, @buffer : Buffer(U))
      @data = @buffer.data
    end

    def ensure_free_capacity
      if @size == @buffer.capacity
        Snapshot.new(@size, @buffer.double_capacity)
      else
        self
      end
    end

    @[AlwaysInline]
    def unsafe_fetch(index : Int)
      @data[index]
    end

    @[AlwaysInline]
    def []=(index : Int, value : U)
      index = check_index_out_of_bounds index
      @data[index] = value
    end

    def [](range : Range)
      self[*Indexable.range_to_index_and_count(range, size)]
    end

    def [](start : Int, count : Int)
      self[start, count]? || raise IndexError.new
    end

    def []?(start : Int, count : Int)
      raise ArgumentError.new "Negative count: #{count}" if count < 0
      return Snapshot.new(0, Buffer(U).new(0)) if start == @size

      start += @size if start < 0

      if 0 <= start <= @size
        return Snapshot.new(0, Buffer(U).new(0)) if count == 0

        count = Math.min(count, @size - start)

        buffer = Buffer(U).new(count)
        buffer.data.copy_from(self.data + start, count)
        Snapshot.new(0, buffer)
      end
    end

    def check_index_out_of_bounds(index)
      check_index_out_of_bounds(index) { raise IndexError.new }
    end

    def to_lookup_hash
      to_lookup_hash { |elem| elem }
    end

    def to_lookup_hash(&block : U -> S) forall S
      each_with_object(Hash(S, U).new) do |o, h|
        key = yield o
        unless h.has_key?(key)
          h[key] = o
        end
      end
    end
  end

  # Order is important for the custom GC mark procedure.
  # See GC.malloc_array. When #7967 is fixed it can be removed.
  @size : Int32
  @element_size : Int32
  @buffer : Buffer(T)

  include Indexable(T)
  include Comparable(Array)

  # Returns the number of elements in the array.
  #
  # ```
  # [:foo, :bar].size # => 2
  # ```
  getter size : Int32

  # Creates a new empty Array.
  def initialize
    @size = 0
    @element_size = sizeof(T)
    @buffer = Buffer(T).new(0)
  end

  # Creates a new empty `Array` backed by a buffer that is initially
  # `initial_capacity` big.
  #
  # The *initial_capacity* is useful to avoid unnecessary reallocations
  # of the internal buffer in case of growth. If you have an estimate
  # of the maximum number of elements an array will hold, the array should
  # be initialized with that capacity for improved performance.
  #
  # ```
  # ary = Array(Int32).new(5)
  # ary.size # => 0
  # ```
  def initialize(initial_capacity : Int)
    if initial_capacity < 0
      raise ArgumentError.new("Negative array size: #{initial_capacity}")
    end

    @size = 0
    @element_size = sizeof(T)
    @buffer = Buffer(T).new(initial_capacity)
  end

  # Creates a new `Array` of the given *size* filled with the same *value* in each position.
  #
  # ```
  # Array.new(3, 'a') # => ['a', 'a', 'a']
  #
  # ary = Array.new(3, [1])
  # ary # => [[1], [1], [1]]
  # ary[0][0] = 2
  # ary # => [[2], [2], [2]]
  # ```
  def initialize(size : Int, value : T)
    if size < 0
      raise ArgumentError.new("Negative array size: #{size}")
    end

    @size = size.to_i
    @element_size = sizeof(T)
    @buffer = Buffer(T).new(@size)
    ptr = @buffer.data
    @size.times { |i| ptr[i] = value }
  end

  def self.allocate
    blob = GC.malloc_array(T).as(Array(T))
    set_crystal_type_id(blob)
    blob
  end

  # :nodoc:
  protected def snapshot
    # Buffer capacity can only increase and
    # is never zeroed so the safe way is to
    # read _first_ the size and then the buffer
    size = @size
    buffer = @buffer

    Snapshot(T).new(size, buffer)
  end

  # :nodoc:
  def self.from_snapshot(s : Snapshot(T))
    Array(T).build(s.buffer.capacity) do |buffer|
      buffer.copy_from(s.data, s.size)
      s.size
    end
  end

  # :nodoc:
  @[AlwaysInline]
  private def set_size_and_buffer(size, buffer)
    # Setting the size and buffers needs to
    # enforce the invariant that size <= buffer.capacity
    # and every point in the execution.
    # It is assumed that:
    #
    #   * @buffer.capacity <= buffer.capacity
    #   * @size <= @buffer.capacity
    #   * size <= buffer.capacity

    @size = Math.min(size, @buffer.capacity)
    @buffer = buffer
    @size = size
  end

  # :nodoc:
  protected def size=(size : Int)
    @size = size.to_i
  end

  # Creates a new `Array` of the given *size* and invokes the given block once
  # for each index of `self`, assigning the block's value in that index.
  #
  # ```
  # Array.new(3) { |i| (i + 1) ** 2 } # => [1, 4, 9]
  #
  # ary = Array.new(3) { [1] }
  # ary # => [[1], [1], [1]]
  # ary[0][0] = 2
  # ary # => [[2], [1], [1]]
  # ```
  def self.new(size : Int, &block : Int32 -> T)
    Array(T).build(size) do |buffer|
      size.to_i.times do |i|
        buffer[i] = yield i
      end
      size
    end
  end

  # Creates a new `Array`, allocating an internal buffer with the given *capacity*,
  # and yielding that buffer. The given block must return the desired size of the array.
  #
  # This method is **unsafe**, but is usually used to initialize the buffer
  # by passing it to a C function.
  #
  # ```
  # Array.build(3) do |buffer|
  #   LibSome.fill_buffer_and_return_number_of_elements_filled(buffer)
  # end
  # ```
  def self.build(capacity : Int) : self
    ary = Array(T).new(capacity)
    ary.size = (yield ary.@buffer.data).to_i
    ary
  end

  # Equality. Returns `true` if each element in `self` is equal to each
  # corresponding element in *other*.
  #
  # ```
  # ary = [1, 2, 3]
  # ary == [1, 2, 3] # => true
  # ary == [2, 3]    # => false
  # ```
  def ==(other : Array)
    equals?(other) { |x, y| x == y }
  end

  # :nodoc:
  def ==(other)
    false
  end

  # Combined comparison operator.
  #
  # Returns `-1`, `0` or `1` depending on whether `self` is less than *other*, equals *other*
  # or is greater than *other*.
  #
  # It compares the elements of both arrays in the same position using the
  # `<=>` operator. As soon as one of such comparisons returns a non-zero
  # value, that result is the return value of the comparison.
  #
  # If all elements are equal, the comparison is based on the size of the arrays.
  #
  # ```
  # [8] <=> [1, 2, 3] # => 1
  # [2] <=> [4, 2, 3] # => -1
  # [1, 2] <=> [1, 2] # => 0
  # ```
  def <=>(other : Array)
    _other = other.snapshot
    _self = self.snapshot

    min_size = Math.min(_self.size, _other.size)
    0.upto(min_size - 1) do |i|
      n = _self.unsafe_fetch(i) <=> _other.unsafe_fetch(i)
      return n if n != 0
    end
    _self.size <=> _other.size
  end

  # Set intersection: returns a new `Array` containing elements common to `self`
  # and *other*, excluding any duplicates. The order is preserved from `self`.
  #
  # ```
  # [1, 1, 3, 5] & [1, 2, 3]               # => [ 1, 3 ]
  # ['a', 'b', 'b', 'z'] & ['a', 'b', 'c'] # => [ 'a', 'b' ]
  # ```
  #
  # See also: `#uniq`.
  def &(other : Array(U)) forall U
    _self = self.snapshot
    _other = other.snapshot

    return Array(T).new if _self.empty? || _other.empty?

    hash = _other.to_lookup_hash
    hash_size = hash.size
    Array(T).build(Math.min(_self.size, _other.size)) do |buffer|
      i = 0
      _self.each do |obj|
        hash.delete(obj)
        new_hash_size = hash.size
        if hash_size != new_hash_size
          hash_size = new_hash_size
          buffer[i] = obj
          i += 1
        end
      end
      i
    end
  end

  # Set union: returns a new `Array` by joining `self` with *other*, excluding
  # any duplicates, and preserving the order from `self`.
  #
  # ```
  # ["a", "b", "c"] | ["c", "d", "a"] # => [ "a", "b", "c", "d" ]
  # ```
  #
  # See also: `#uniq`.
  def |(other : Array(U)) forall U
    _self = self.snapshot
    _other = other.snapshot

    Array(T | U).build(_self.size + _other.size) do |buffer|
      hash = Hash(T, Bool).new
      i = 0
      _self.each do |obj|
        unless hash.has_key?(obj)
          buffer[i] = obj
          hash[obj] = true
          i += 1
        end
      end
      _other.each do |obj|
        unless hash.has_key?(obj)
          buffer[i] = obj
          hash[obj] = true
          i += 1
        end
      end
      i
    end
  end

  # Concatenation. Returns a new `Array` built by concatenating `self` and *other*.
  # The type of the new array is the union of the types of both the original arrays.
  #
  # ```
  # [1, 2] + ["a"]  # => [1,2,"a"] of (Int32 | String)
  # [1, 2] + [2, 3] # => [1,2,2,3]
  # ```
  def +(other : Array(U)) forall U
    _self = self.snapshot
    _other = other.snapshot
    new_size = _self.size + _other.size
    Array(T | U).build(new_size) do |buffer|
      buffer.copy_from(_self.data, _self.size)
      (buffer + _self.size).copy_from(_other.data, _other.size)
      new_size
    end
  end

  # Difference. Returns a new `Array` that is a copy of `self`, removing any items
  # that appear in *other*. The order of `self` is preserved.
  #
  # ```
  # [1, 2, 3] - [2, 1] # => [3]
  # ```
  def -(other : Array(U)) forall U
    _other = other.snapshot
    ary = Array(T).new(Math.max(size - _other.size, 0))
    hash = _other.to_lookup_hash
    each do |obj|
      ary << obj unless hash.has_key?(obj)
    end
    ary
  end

  # Repetition: Returns a new `Array` built by concatenating *times* copies of `self`.
  #
  # ```
  # ["a", "b", "c"] * 2 # => [ "a", "b", "c", "a", "b", "c" ]
  # ```
  def *(times : Int)
    ary = Array(T).new(size * times)
    times.times do
      ary.concat(self)
    end
    ary
  end

  # Append. Alias for `push`.
  #
  # ```
  # a = [1, 2]
  # a << 3 # => [1,2,3]
  # ```
  def <<(value : T)
    push(value)
  end

  # Sets the given value at the given index.
  #
  # Negative indices can be used to start counting from the end of the array.
  # Raises `IndexError` if trying to set an element outside the array's range.
  #
  # ```
  # ary = [1, 2, 3]
  # ary[0] = 5
  # p ary # => [5,2,3]
  #
  # ary[3] = 5 # raises IndexError
  # ```
  @[AlwaysInline]
  def []=(index : Int, value : T)
    # The bound check is performed in array level
    # to avoid raising always an Array::Snapshot exception.
    check_index_out_of_bounds(index)
    _self = self.snapshot
    index = _self.check_index_out_of_bounds index

    _self.data[index] = value
  end

  # Replaces a subrange with a single value. All elements in the range
  # `index...index+count` are removed and replaced by a single element
  # *value*.
  #
  # If *count* is zero, *value* is inserted at *index*.
  #
  # Negative values of *index* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = 6
  # a # => [1, 6, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 0] = 6
  # a # => [1, 6, 2, 3, 4, 5]
  # ```
  def []=(index : Int, count : Int, value : T)
    raise ArgumentError.new "Negative count: #{count}" if count < 0

    check_index_out_of_bounds index
    _self = self.snapshot
    index = _self.check_index_out_of_bounds index

    count = index + count <= _self.size ? count : _self.size - index

    case count
    when 0
      insert index, value
    when 1
      _self.data[index] = value
    else
      diff = count - 1
      (_self.data + index + 1).move_from(_self.data + index + count, _self.size - index - count)
      _self[index] = value

      set_size_and_buffer(_self.size - diff, _self.buffer)
    end

    value
  end

  # Replaces a subrange with a single value.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = 6
  # a # => [1, 6, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1...1] = 6
  # a # => [1, 6, 2, 3, 4, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[2...] = 6
  # a # => [1, 2, 6]
  # ```
  def []=(range : Range, value : T)
    self[*Indexable.range_to_index_and_count(range, size)] = value
  end

  # Replaces a subrange with the elements of the given array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7, 8]
  # a # => [1, 6, 7, 8, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7]
  # a # => [1, 6, 7, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7, 8, 9, 10]
  # a # => [1, 6, 7, 8, 9, 10, 5]
  # ```
  def []=(index : Int, count : Int, values : Array(T))
    raise ArgumentError.new "Negative count: #{count}" if count < 0

    check_index_out_of_bounds index
    _self = self.snapshot
    index = _self.check_index_out_of_bounds index
    _values = values.snapshot

    count = index + count <= _self.size ? count : _self.size - index
    diff = _values.size - count

    if diff == 0
      # Replace values directly
      (_self.data + index).copy_from(_values.data, _values.size)
    elsif diff < 0
      # Need to shrink
      diff = -diff
      (_self.data + index).copy_from(_values.data, _values.size)
      (_self.data + index + _values.size).move_from(_self.data + index + count, _self.size - index - count)
      set_size_and_buffer(_self.size - diff, _self.buffer)
    else
      # Need to grow
      new_buffer = _self.buffer.ensure_capacity(_self.size + diff)
      (new_buffer.data + index + _values.size).move_from(new_buffer.data + index + count, _self.size - index - count)
      (new_buffer.data + index).copy_from(_values.data, _values.size)
      set_size_and_buffer(_self.size + diff, new_buffer)
    end

    values
  end

  # Replaces a subrange with the elements of the given array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7, 8]
  # a # => [1, 6, 7, 8, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7]
  # a # => [1, 6, 7, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7, 8, 9, 10]
  # a # => [1, 6, 7, 8, 9, 10, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[2..] = [6, 7, 8, 9, 10]
  # a # => [1, 2, 6, 7, 8, 9, 10]
  # ```
  def []=(range : Range, values : Array(T))
    self[*Indexable.range_to_index_and_count(range, size)] = values
  end

  # Returns all elements that are within the given range.
  #
  # Negative indices count backward from the end of the array (-1 is the last
  # element). Additionally, an empty array is returned when the starting index
  # for an element range is at the end of the array.
  #
  # Raises `IndexError` if the range's start is out of range.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[1..3]    # => ["b", "c", "d"]
  # a[4..7]    # => ["e"]
  # a[6..10]   # raise IndexError
  # a[5..10]   # => []
  # a[-2...-1] # => ["d"]
  # a[2..]     # => ["c", "d", "e"]
  # ```
  def [](range : Range)
    self[*Indexable.range_to_index_and_count(range, size)]
  end

  # Like `#[Range(Int, Int)]`, but returns `nil` if the range's start is out of range.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[6..10]? # => nil
  # ```
  def []?(range : Range(Int, Int))
    self[*Indexable.range_to_index_and_count(range, size)]?
  end

  # Returns count or less (if there aren't enough) elements starting at the
  # given start index.
  #
  # Negative indices count backward from the end of the array (-1 is the last
  # element). Additionally, an empty array is returned when the starting index
  # for an element range is at the end of the array.
  #
  # Raises `IndexError` if the *start* index is out of range.
  #
  # Raises `ArgumentError` if *count* is negative.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[-3, 3] # => ["c", "d", "e"]
  # a[1, 2]  # => ["b", "c"]
  # a[5, 1]  # => []
  # a[6, 1]  # raises IndexError
  # ```
  def [](start : Int, count : Int)
    self[start, count]? || raise IndexError.new
  end

  # Like `#[Int, Int]` but returns `nil` if the *start* index is out of range.
  def []?(start : Int, count : Int)
    raise ArgumentError.new "Negative count: #{count}" if count < 0
    _self = self.snapshot
    return Array(T).new if start == _self.size

    start += _self.size if start < 0

    if 0 <= start <= _self.size
      return Array(T).new if count == 0

      count = Math.min(count, _self.size - start)

      Array(T).build(count) do |buffer|
        buffer.copy_from(_self.data + start, count)
        count
      end
    end
  end

  @[AlwaysInline]
  def unsafe_fetch(index : Int)
    @buffer.data[index]
  end

  # Removes all elements from self.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a.clear # => []
  # ```
  def clear
    # An invariant of the array is that the buffer is never
    # shrinked, not zeroed.
    @size = 0
    self
  end

  # Returns a new `Array` that has `self`'s elements cloned.
  # That is, it returns a deep copy of `self`.
  #
  # Use `#dup` if you want a shallow copy.
  #
  # ```
  # ary = [[1, 2], [3, 4]]
  # ary2 = ary.clone
  # ary[0][0] = 5
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[1, 2], [3, 4]]
  #
  # ary2 << [7, 8]
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[1, 2], [3, 4], [7, 8]]
  # ```
  def clone
    _self = self.snapshot
    Array(T).new(_self.size) { |i| _self.data[i].clone.as(T) }
  end

  # Returns a copy of `self` with all `nil` elements removed.
  #
  # ```
  # ["a", nil, "b", nil, "c", nil].compact # => ["a", "b", "c"]
  # ```
  def compact
    compact_map &.itself
  end

  # Removes all `nil` elements from `self` and returns `self`.
  #
  # ```
  # ary = ["a", nil, "b", nil, "c"]
  # ary.compact!
  # ary # => ["a", "b", "c"]
  # ```
  def compact!
    reject! &.nil?
  end

  # Appends the elements of *other* to `self`, and returns `self`.
  #
  # ```
  # ary = ["a", "b"]
  # ary.concat(["c", "d"])
  # ary # => ["a", "b", "c", "d"]
  # ```
  def concat(other : Array)
    concat(other.snapshot)
  end

  # ditto
  def concat(other : Enumerable)
    _self = self.snapshot

    len = _self.size
    left_before_resize = _self.buffer.capacity - len
    buf = _self.buffer.data + len

    other.each do |elem|
      if left_before_resize == 0
        _self = Snapshot(T).new(_self.size, _self.buffer.double_capacity)

        left_before_resize = _self.buffer.capacity - len
        buf = _self.buffer.data + len
      end
      buf.value = elem
      buf += 1
      len += 1
      left_before_resize -= 1
    end

    set_size_and_buffer(len, _self.buffer)

    self
  end

  private def concat(other : Snapshot(T))
    _self = self.snapshot
    new_size = _self.size + other.size
    new_buffer = _self.buffer.ensure_capacity(new_size)

    (new_buffer.data + _self.size).copy_from(other.data, other.size)

    set_size_and_buffer(new_size, new_buffer)

    self
  end

  # Removes all items from `self` that are equal to *obj*.
  #
  # Returns the last found element that was equal to *obj*,
  # if any, or `nil` if not found.
  #
  # ```
  # a = ["a", "b", "b", "b", "c"]
  # a.delete("b") # => "b"
  # a             # => ["a", "c"]
  #
  # a.delete("x") # => nil
  # a             # => ["a", "c"]
  # ```
  def delete(obj)
    internal_delete { |e| e == obj }[1]
  end

  # Removes the element at *index*, returning that element.
  # Raises `IndexError` if *index* is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(2)  # => "cat"
  # a               # => ["ant", "bat", "dog"]
  # a.delete_at(99) # raises IndexError
  # ```
  def delete_at(index : Int)
    check_index_out_of_bounds index
    _self = self.snapshot
    index = _self.check_index_out_of_bounds index

    elem = _self.data[index]
    (_self.data + index).move_from(_self.data + index + 1, _self.size - index - 1)
    set_size_and_buffer(_self.size - 1, _self.buffer)
    elem
  end

  # Removes all elements within the given *range*.
  # Returns an array of the removed elements with the original order of `self` preserved.
  # Raises `IndexError` if the index is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(1..2)    # => ["bat", "cat"]
  # a                    # => ["ant", "dog"]
  # a.delete_at(99..100) # raises IndexError
  # ```
  def delete_at(range : Range)
    index, count = Indexable.range_to_index_and_count(range, self.size)
    delete_at(index, count)
  end

  # Removes *count* elements from `self` starting at *index*.
  # If the size of `self` is less than *count*, removes values to the end of the array without error.
  # Returns an array of the removed elements with the original order of `self` preserved.
  # Raises `IndexError` if *index* is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(1, 2)  # => ["bat", "cat"]
  # a                  # => ["ant", "dog"]
  # a.delete_at(99, 1) # raises IndexError
  # ```
  def delete_at(index : Int, count : Int)
    val = self[index, count]
    _self = self.snapshot
    count = index + count <= _self.size ? count : _self.size - index
    (_self.data + index).move_from(_self.data + index + count, _self.size - index - count)
    set_size_and_buffer(_self.size - count, _self.buffer)
    val
  end

  # Returns a new `Array` that has exactly `self`'s elements.
  # That is, it returns a shallow copy of `self`.
  #
  # Use `#clone` if you want a deep copy.
  #
  # ```
  # ary = [[1, 2], [3, 4]]
  # ary2 = ary.dup
  # ary[0][0] = 5
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[5, 2], [3, 4]]
  #
  # ary2 << [7, 8]
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[5, 2], [3, 4], [7, 8]]
  # ```
  def dup
    Array.from_snapshot(self.snapshot)
  end

  # Yields each index of `self` to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # ```
  # a = [1, 2, 3, 4]
  # a.fill { |i| i * i } # => [0, 1, 4, 9]
  # ```
  def fill
    _self = self.snapshot
    _self.each_index { |i| _self.data[i] = yield i }

    self
  end

  # Yields each index of `self`, starting at *from*, to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # Raises `IndexError` if *from* is outside the array range.
  #
  # ```
  # a = [1, 2, 3, 4]
  # a.fill(2) { |i| i * i } # => [1, 2, 4, 9]
  # ```
  def fill(from : Int)
    _self = self.snapshot

    from += _self.size if from < 0

    raise IndexError.new unless 0 <= from < _self.size

    from.upto(_self.size - 1) { |i| _self.data[i] = yield i }

    self
  end

  # Yields each index of `self`, starting at *from* and just *count* times,
  # to the given block and then assigns the block's value in that position. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # Raises `IndexError` if *from* is outside the array range.
  #
  # Has no effect if *count* is zero or negative.
  #
  # ```
  # a = [1, 2, 3, 4, 5, 6]
  # a.fill(2, 2) { |i| i * i } # => [1, 2, 4, 9, 5, 6]
  # ```
  def fill(from : Int, count : Int)
    return self if count <= 0

    _self = self.snapshot
    from += _self.size if from < 0

    raise IndexError.new unless 0 <= from < _self.size && from + count <= _self.size

    from.upto(from + count - 1) { |i| _self.data[i] = yield i }

    self
  end

  # Yields each index of `self`, in the given *range*, to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # ```
  # a = [1, 2, 3, 4, 5, 6]
  # a.fill(2..3) { |i| i * i } # => [1, 2, 4, 9, 5, 6]
  # ```
  def fill(range : Range)
    fill(*Indexable.range_to_index_and_count(range, size)) do |i|
      yield i
    end
  end

  # Replaces every element in `self` with the given *value*. Returns `self`.
  #
  # ```
  # a = [1, 2, 3]
  # a.fill(9) # => [9, 9, 9]
  # ```
  def fill(value : T)
    fill { value }
  end

  # Replaces every element in `self`, starting at *from*, with the given *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2) # => [1, 2, 9, 9, 9]
  # ```
  def fill(value : T, from : Int)
    fill(from) { value }
  end

  # Replaces every element in `self`, starting at *from* and only *count* times,
  # with the given *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2, 2) # => [1, 2, 9, 9, 5]
  # ```
  def fill(value : T, from : Int, count : Int)
    fill(from, count) { value }
  end

  # Replaces every element in *range* with *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2..3) # => [1, 2, 9, 9, 5]
  # ```
  def fill(value : T, range : Range)
    fill(range) { value }
  end

  # Returns the first *n* elements of the array.
  #
  # ```
  # [1, 2, 3].first(2) # => [1, 2]
  # [1, 2, 3].first(4) # => [1, 2, 3]
  # ```
  def first(n : Int)
    self[0, n]
  end

  # Insert *object* before the element at *index* and shifting successive elements, if any.
  # Returns `self`.
  #
  # Negative values of *index* count from the end of the array.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.insert(0, "x")  # => ["x", "a", "b", "c"]
  # a.insert(2, "y")  # => ["x", "a", "y", "b", "c"]
  # a.insert(-1, "z") # => ["x", "a", "y", "b", "c", "z"]
  # ```
  def insert(index : Int, object : T)
    _self = self.snapshot.ensure_free_capacity

    if index < 0
      index += _self.size + 1
    end

    unless 0 <= index <= _self.size
      raise IndexError.new
    end

    (_self.data + index + 1).move_from(_self.data + index, size - index)
    _self.data[index] = object

    set_size_and_buffer(_self.size + 1, _self.buffer)
    self
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    to_s io
  end

  # Returns the last *n* elements of the array.
  #
  # ```
  # [1, 2, 3].last(2) # => [2, 3]
  # [1, 2, 3].last(4) # => [1, 2, 3]
  # ```
  def last(n : Int)
    if n < @size
      self[@size - n, n]
    else
      dup
    end
  end

  # Since the buffer is only increased and never zeroed
  # the default implementation of `Indexable#each` is already Thread-safe.

  # Optimized version of `Enumerable#map`.
  def map(&block : T -> U) forall U
    _self = self.snapshot
    Array(U).new(_self.size) { |i| yield _self.data[i] }
  end

  # Invokes the given block for each element of `self`, replacing the element
  # with the value returned by the block. Returns `self`.
  #
  # ```
  # a = [1, 2, 3]
  # a.map! { |x| x * x }
  # a # => [1, 4, 9]
  # ```
  def map!
    _self = self.snapshot
    _self.data.map!(_self.size) { |e| yield e }
    self
  end

  # Modifies `self`, keeping only the elements in the collection for which the
  # passed block returns `true`. Returns `self`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.select! { |x| x > 3 }
  # ary # => [6, 4, 8]
  # ```
  #
  # See also: `Array#select`.
  def select!
    reject! { |elem| !yield(elem) }
  end

  # Modifies `self`, keeping only the elements in the collection for which
  # `pattern === element`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.select!(3..7)
  # ary # => [6, 4]
  # ```
  #
  # See also: `Array#reject!`.
  def select!(pattern)
    self.select! { |elem| pattern === elem }
  end

  # Modifies `self`, deleting the elements in the collection for which the
  # passed block returns `true`. Returns `self`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.reject! { |x| x > 3 }
  # ary # => [1, 2]
  # ```
  #
  # See also: `Array#reject`.
  def reject!
    internal_delete { |e| yield e }
    self
  end

  # Modifies `self`, deleting the elements in the collection for which
  # `pattern === element`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.reject!(3..7)
  # ary # => [1, 2, 8]
  # ```
  #
  # See also: `Array#select!`.
  def reject!(pattern)
    reject! { |elem| pattern === elem }
    self
  end

  # `reject!` and `delete` implementation: returns a tuple {x, y}
  # with x being self/nil (modified, not modified)
  # and y being the last matching element, or nil
  private def internal_delete
    _self = self.snapshot
    i1 = 0
    i2 = 0
    match = nil
    while i1 < _self.size
      e = _self.data[i1]
      if yield e
        match = e
      else
        if i1 != i2
          _self.data[i2] = e
        end
        i2 += 1
      end

      i1 += 1
    end

    if i2 != i1
      count = i1 - i2
      set_size_and_buffer(_self.size - count, _self.buffer)
      {self, match}
    else
      {nil, match}
    end
  end

  # Optimized version of `Enumerable#map_with_index`.
  def map_with_index(&block : T, Int32 -> U) forall U
    _self = self.snapshot
    Array(U).new(_self.size) { |i| yield _self.data[i], i }
  end

  # Like `map_with_index`, but mutates `self` instead of allocating a new object.
  def map_with_index!(&block : (T, Int32) -> T)
    _self = self.snapshot
    _self.data.map_with_index!(_self.size) { |e, i| yield e, i }
    self
  end

  # Returns an `Array` with the first *count* elements removed
  # from the original array.
  #
  # If *count* is bigger than the number of elements in the array, returns an empty array.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].skip(3) # => [4, 5, 6]
  # ```
  def skip(count : Int) : Array(T)
    raise ArgumentError.new("Attempt to skip negative size") if count < 0

    _self = self.snapshot
    new_size = Math.max(_self.size - count, 0)
    Array(T).build(new_size) do |buffer|
      buffer.copy_from(_self.data + count, new_size)
      new_size
    end
  end

  # Returns an `Array` with all possible permutations of *size*.
  #
  # ```
  # a = [1, 2, 3]
  # a.permutations    # => [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
  # a.permutations(1) # => [[1],[2],[3]]
  # a.permutations(2) # => [[1,2],[1,3],[2,1],[2,3],[3,1],[3,2]]
  # a.permutations(3) # => [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
  # a.permutations(0) # => [[]]
  # a.permutations(4) # => []
  # ```
  def permutations(size : Int = self.size)
    ary = [] of Array(T)
    each_permutation(size) do |a|
      ary << a
    end
    ary
  end

  # Yields each possible permutation of *size* of `self`.
  #
  # ```
  # a = [1, 2, 3]
  # sums = [] of Int32
  # a.each_permutation(2) { |p| sums << p.sum } # => nil
  # sums                                        # => [3, 4, 3, 5, 4, 5]
  # ```
  #
  # By default, a new array is created and yielded for each permutation.
  # If *reuse* is given, the array can be reused: if *reuse* is
  # an `Array`, this array will be reused; if *reuse* if truthy,
  # the method will create a new array and reuse it. This can be
  # used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def each_permutation(size : Int = self.size, reuse = false) : Nil
    n = self.size
    return if size > n

    raise ArgumentError.new("Size must be positive") if size < 0

    reuse = check_reuse(reuse, size)
    pool = self.dup
    cycles = (n - size + 1..n).to_a.reverse!
    yield pool_slice(pool, size, reuse)

    while true
      stop = true
      i = size - 1
      while i >= 0
        ci = (cycles[i] -= 1)
        if ci == 0
          e = pool[i]
          (i + 1).upto(n - 1) { |j| pool[j - 1] = pool[j] }
          pool[n - 1] = e
          cycles[i] = n - i
        else
          pool.swap i, -ci
          yield pool_slice(pool, size, reuse)
          stop = false
          break
        end
        i -= 1
      end

      return if stop
    end
  end

  # Returns an `Iterator` over each possible permutation of *size* of `self`.
  #
  # ```
  # iter = [1, 2, 3].each_permutation
  # iter.next # => [1, 2, 3]
  # iter.next # => [1, 3, 2]
  # iter.next # => [2, 1, 3]
  # iter.next # => [2, 3, 1]
  # iter.next # => [3, 1, 2]
  # iter.next # => [3, 2, 1]
  # iter.next # => #<Iterator::Stop>
  # ```
  #
  # By default, a new array is created and returned for each permutation.
  # If *reuse* is given, the array can be reused: if *reuse* is
  # an `Array`, this array will be reused; if *reuse* if truthy,
  # the method will create a new array and reuse it. This can be
  # used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def each_permutation(size : Int = self.size, reuse = false)
    raise ArgumentError.new("Size must be positive") if size < 0

    PermutationIterator.new(self, size.to_i, reuse)
  end

  def combinations(size : Int = self.size)
    ary = [] of Array(T)
    each_combination(size) do |a|
      ary << a
    end
    ary
  end

  def each_combination(size : Int = self.size, reuse = false) : Nil
    n = self.size
    return if size > n
    raise ArgumentError.new("Size must be positive") if size < 0

    reuse = check_reuse(reuse, size)
    copy = self.dup
    pool = self.dup

    indices = (0...size).to_a

    yield pool_slice(pool, size, reuse)

    while true
      stop = true
      i = size - 1
      while i >= 0
        if indices[i] != i + n - size
          stop = false
          break
        end
        i -= 1
      end

      return if stop

      indices[i] += 1
      pool[i] = copy[indices[i]]

      (i + 1).upto(size - 1) do |j|
        indices[j] = indices[j - 1] + 1
        pool[j] = copy[indices[j]]
      end

      yield pool_slice(pool, size, reuse)
    end
  end

  private def each_combination_piece(pool, size, reuse)
    if reuse
      reuse.clear
      size.times { |i| reuse << pool[i] }
      reuse
    else
      pool[0, size]
    end
  end

  def each_combination(size : Int = self.size, reuse = false)
    raise ArgumentError.new("Size must be positive") if size < 0

    CombinationIterator.new(self, size.to_i, reuse)
  end

  private def check_reuse(reuse, size)
    if reuse
      unless reuse.is_a?(Array)
        reuse = typeof(self).new(size)
      end
    else
      reuse = nil
    end
    reuse
  end

  # Returns a new `Array` that is a one-dimensional flattening of `self` (recursively).
  #
  # That is, for every element that is an array or an iterator, extract its elements into the new array.
  #
  # ```
  # s = [1, 2, 3]          # => [1, 2, 3]
  # t = [4, 5, 6, [7, 8]]  # => [4, 5, 6, [7, 8]]
  # u = [9, [10, 11].each] # => [9, #<Indexable::ItemIterator>]
  # a = [s, t, u, 12, 13]  # => [[1, 2, 3], [4, 5, 6, [7, 8]], 9, #<Indexable::ItemIterator>, 12, 13]
  # a.flatten              # => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
  # ```
  def flatten
    FlattenHelper(typeof(FlattenHelper.element_type(self))).flatten(self)
  end

  def repeated_combinations(size : Int = self.size)
    ary = [] of Array(T)
    each_repeated_combination(size) do |a|
      ary << a
    end
    ary
  end

  def each_repeated_combination(size : Int = self.size, reuse = false) : Nil
    n = self.size
    return if size > n && n == 0
    raise ArgumentError.new("Size must be positive") if size < 0

    reuse = check_reuse(reuse, size)
    copy = self.dup
    indices = Array.new(size, 0)
    pool = indices.map { |i| copy[i] }

    yield pool_slice(pool, size, reuse)

    while true
      stop = true

      i = size - 1
      while i >= 0
        if indices[i] != n - 1
          stop = false
          break
        end
        i -= 1
      end
      return if stop

      ii = indices[i] + 1
      tmp = copy[ii]
      indices.fill(i, size - i) { ii }
      pool.fill(i, size - i) { tmp }

      yield pool_slice(pool, size, reuse)
    end
  end

  def each_repeated_combination(size : Int = self.size, reuse = false)
    raise ArgumentError.new("Size must be positive") if size < 0

    RepeatedCombinationIterator.new(self, size.to_i, reuse)
  end

  def self.product(arrays)
    result = [] of Array(typeof(arrays.first.first))
    each_product(arrays) do |product|
      result << product
    end
    result
  end

  def self.product(*arrays : Array)
    product(arrays.to_a)
  end

  def self.each_product(arrays : Array(Array), reuse = false)
    lens = arrays.map &.size
    return if lens.any? &.==(0)

    pool = arrays.map &.first

    n = arrays.size
    indices = Array.new(n, 0)

    if reuse
      unless reuse.is_a?(Array)
        reuse = typeof(pool).new(n)
      end
    else
      reuse = nil
    end

    yield pool_slice(pool, n, reuse)

    while true
      i = n - 1
      indices[i] += 1

      while indices[i] >= lens[i]
        indices[i] = 0
        pool[i] = arrays[i][indices[i]]
        i -= 1
        return if i < 0
        indices[i] += 1
      end
      pool[i] = arrays[i][indices[i]]
      yield pool_slice(pool, n, reuse)
    end
  end

  def self.each_product(*arrays : Array, reuse = false)
    each_product(arrays.to_a, reuse: reuse) do |result|
      yield result
    end
  end

  def repeated_permutations(size : Int = self.size)
    ary = [] of Array(T)
    each_repeated_permutation(size) do |a|
      ary << a
    end
    ary
  end

  def each_repeated_permutation(size : Int = self.size, reuse = false) : Nil
    n = self.size
    return if size != 0 && n == 0
    raise ArgumentError.new("Size must be positive") if size < 0

    if size == 0
      yield([] of T)
    else
      Array.each_product(Array.new(size, self), reuse: reuse) { |r| yield r }
    end
  end

  # Removes the last value from `self`, at index *size - 1*.
  # This method returns the removed value.
  # Raises `IndexError` if array is of 0 size.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.pop # => "c"
  # a     # => ["a", "b"]
  # ```
  def pop
    pop { raise IndexError.new }
  end

  # Removes the last value from `self`.
  # If the array is empty, the given block is called.
  #
  # ```
  # a = [1]
  # a.pop { "Testing" } # => 1
  # a.pop { "Testing" } # => "Testing"
  # ```
  def pop
    _self = self.snapshot

    if _self.size == 0
      yield
    else
      new_size = _self.size - 1
      value = _self.data[new_size]
      set_size_and_buffer(new_size, _self.buffer)
      value
    end
  end

  # Removes the last *n* values from `self`, at index *size - 1*.
  # This method returns an array of the removed values, with the original order preserved.
  #
  # If *n* is greater than the size of `self`, all values will be removed from `self`
  # without raising an error.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.pop(2) # => ["b", "c"]
  # a        # => ["a"]
  #
  # a = ["a", "b", "c"]
  # a.pop(4) # => ["a", "b", "c"]
  # a        # => []
  # ```
  def pop(n : Int)
    if n < 0
      raise ArgumentError.new("Can't pop negative count")
    end

    _self = self.snapshot

    n = Math.min(n, _self.size)
    ary = Array(T).new(n) { |i| _self.data[_self.size - n + i] }

    new_size = @size - n
    set_size_and_buffer(new_size, _self.buffer)

    ary
  end

  # Like `pop`, but returns `nil` if `self` is empty.
  def pop?
    pop { nil }
  end

  def product(ary : Array(U)) forall U
    result = Array({T, U}).new(size * ary.size)
    product(ary) do |x, y|
      result << {x, y}
    end
    result
  end

  def product(enumerable : Enumerable, &block)
    self.each { |a| enumerable.each { |b| yield a, b } }
  end

  # Append. Pushes one value to the end of `self`, given that the type of the value is *T*
  # (which might be a single type or a union of types).
  # This method returns `self`, so several calls can be chained.
  # See `pop` for the opposite effect.
  #
  # ```
  # a = ["a", "b"]
  # a.push("c") # => ["a", "b", "c"]
  # a.push(1)   # Errors, because the array only accepts String.
  #
  # a = ["a", "b"] of (Int32 | String)
  # a.push("c") # => ["a", "b", "c"]
  # a.push(1)   # => ["a", "b", "c", 1]
  # ```
  def push(value : T)
    _self = self.snapshot.ensure_free_capacity
    _self.data[_self.size] = value

    set_size_and_buffer(_self.size + 1, _self.buffer)
    self
  end

  # Append multiple values. The same as `push`, but takes an arbitrary number
  # of values to push into `self`. Returns `self`.
  #
  # ```
  # a = ["a"]
  # a.push("b", "c") # => ["a", "b", "c"]
  # ```
  def push(*values : T)
    _self = self.snapshot
    new_size = _self.size + values.size
    new_buffer = _self.buffer.ensure_capacity(new_size)

    values.each_with_index do |value, i|
      new_buffer.data[_self.size + i] = value
    end

    set_size_and_buffer(new_size, new_buffer)
    self
  end

  def replace(other : Array)
    _self = self.snapshot
    _other = other.snapshot

    new_buffer = _self.buffer.ensure_capacity(_other.size)
    new_buffer.data.copy_from(_other.data, _other.size)

    set_size_and_buffer(_other.size, new_buffer)
    self
  end

  # Returns an array with all the elements in the collection reversed.
  #
  # ```
  # a = [1, 2, 3]
  # a.reverse # => [3, 2, 1]
  # ```
  def reverse
    _self = self.snapshot
    Array(T).new(_self.size) { |i| _self.data[_self.size - i - 1] }
  end

  # Reverses in-place all the elements of `self`.
  def reverse!
    _self = self.snapshot
    Slice.new(_self.data, _self.size).reverse!
    self
  end

  def rotate!(n = 1)
    _self = self.snapshot

    return self if _self.size == 0
    n %= _self.size
    return self if n == 0
    if n <= _self.size // 2
      tmp = _self[0..n]
      _self.data.move_from(_self.data + n, size - n)
      (_self.data + size - n).copy_from(tmp.data, n)
    else
      tmp = _self[n..-1]
      (_self.data + size - n).move_from(_self.data, n)
      _self.data.copy_from(tmp.data, size - n)
    end
    self
  end

  def rotate(n = 1)
    _self = self.snapshot
    return self if _self.size == 0
    n %= _self.size
    return self if n == 0
    res = Array(T).new(_self.size)
    res.to_unsafe.copy_from(_self.data + n, size - n)
    (res.to_unsafe + size - n).copy_from(_self.data, n)
    res.size = size
    res
  end

  # Returns *n* number of random elements from `self`, using the given *random* number generator.
  # Raises IndexError if `self` is empty.
  #
  # ```
  # a = [1, 2, 3]
  # a.sample(2)                # => [2, 1]
  # a.sample(2, Random.new(1)) # => [1, 3]
  # ```
  def sample(n : Int, random = Random::DEFAULT)
    if n < 0
      raise ArgumentError.new("Can't get negative count sample")
    end

    case n
    when 0
      return [] of T
    when 1
      return [sample(random)] of T
    else
      _self = self.snapshot
      if n >= _self.size
        return Array.from_snapshot(_self).shuffle!(random)
      end

      ary = Array(T).new(n) { |i| _self.data[i] }
      buffer = ary.to_unsafe

      n.upto(size - 1) do |i|
        j = random.rand(i + 1)
        if j <= n
          buffer[j] = _self.data[i]
        end
      end
      ary.shuffle!(random)

      ary
    end
  end

  # Removes the first value of `self`, at index 0. This method returns the removed value.
  # If the array is empty, it raises `IndexError`.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.shift # => "a"
  # a       # => ["b", "c"]
  # ```
  def shift
    shift { raise IndexError.new }
  end

  def shift
    _self = self.snapshot

    if _self.size == 0
      yield
    else
      value = _self.data[0]
      new_size = _self.size - 1
      _self.data.move_from(_self.data + 1, new_size)
      set_size_and_buffer(new_size, _self.buffer)
      value
    end
  end

  # Removes the first *n* values of `self`, starting at index 0.
  # This method returns an array of the removed values.
  #
  # If *n* is greater than the size of `self`, all values will be removed from `self`
  # without raising an error.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.shift # => "a"
  # a       # => ["b", "c"]
  #
  # a = ["a", "b", "c"]
  # a.shift(4) # => ["a", "b", "c"]
  # a          # => []
  # ```
  def shift(n : Int)
    if n < 0
      raise ArgumentError.new("Can't shift negative count")
    end

    _self = self.snapshot
    n = Math.min(n, _self.size)
    ary = Array(T).new(n) { |i| _self.data[i] }

    _self.data.move_from(_self.data + n, _self.size - n)
    set_size_and_buffer(_self.size - n, _self.buffer)

    ary
  end

  # Removes the first value of `self`, at index 0. This method returns the removed value.
  # If the array is empty, it returns `nil` without raising any error.
  #
  # ```
  # a = ["a", "b"]
  # a.shift? # => "a"
  # a        # => ["b"]
  # a.shift? # => "b"
  # a        # => []
  # a.shift? # => nil
  # a        # => []
  # ```
  def shift?
    shift { nil }
  end

  # Returns an array with all the elements in the collection randomized
  # using the given *random* number generator.
  def shuffle(random = Random::DEFAULT)
    dup.shuffle!(random)
  end

  # Modifies `self` by randomizing the order of elements in the collection
  # using the given *random* number generator. Returns `self`.
  def shuffle!(random = Random::DEFAULT)
    _self = self.snapshot
    _self.data.shuffle!(_self.size, random)
    self
  end

  # Returns a new array with all elements sorted based on the return value of
  # their comparison method `#<=>`
  #
  # ```
  # a = [3, 1, 2]
  # a.sort # => [1, 2, 3]
  # a      # => [3, 1, 2]
  # ```
  def sort : Array(T)
    dup.sort!
  end

  # Returns a new array with all elements sorted based on the comparator in the
  # given block.
  #
  # The block must implement a comparison between two elements *a* and *b*,
  # where `a < b` returns `-1`, `a == b` returns `0`, and `a > b` returns `1`.
  # The comparison operator `<=>` can be used for this.
  #
  # ```
  # a = [3, 1, 2]
  # b = a.sort { |a, b| b <=> a }
  #
  # b # => [3, 2, 1]
  # a # => [3, 1, 2]
  # ```
  def sort(&block : T, T -> U) : Array(T) forall U
    {% unless U <= Int32? %}
      {% raise "expected block to return Int32 or Nil, not #{U}" %}
    {% end %}

    dup.sort! &block
  end

  # Modifies `self` by sorting all elements based on the return value of their
  # comparison method `#<=>`
  #
  # ```
  # a = [3, 1, 2]
  # a.sort!
  # a # => [1, 2, 3]
  # ```
  def sort! : Array(T)
    _self = self.snapshot
    Slice.new(_self.data, _self.size).sort!
    self
  end

  # Modifies `self` by sorting all elements based on the comparator in the given
  # block.
  #
  # The given block must implement a comparison between two elements
  # *a* and *b*, where `a < b` returns `-1`, `a == b` returns `0`,
  # and `a > b` returns `1`.
  # The comparison operator `<=>` can be used for this.
  #
  # ```
  # a = [3, 1, 2]
  # a.sort! { |a, b| b <=> a }
  # a # => [3, 2, 1]
  # ```
  def sort!(&block : T, T -> U) : Array(T) forall U
    {% unless U <= Int32? %}
      {% raise "expected block to return Int32 or Nil, not #{U}" %}
    {% end %}

    _self = self.snapshot
    Slice.new(_self.data, _self.size).sort!(&block)
    self
  end

  # Returns a new array with all elements sorted. The given block is called for
  # each element, then the comparison method #<=> is called on the object
  # returned from the block to determine sort order.
  #
  # ```
  # a = %w(apple pear fig)
  # b = a.sort_by { |word| word.size }
  # b # => ["fig", "pear", "apple"]
  # a # => ["apple", "pear", "fig"]
  # ```
  def sort_by(&block : T -> _) : Array(T)
    dup.sort_by! { |e| yield(e) }
  end

  # Modifies `self` by sorting all elements. The given block is called for
  # each element, then the comparison method #<=> is called on the object
  # returned from the block to determine sort order.
  #
  # ```
  # a = %w(apple pear fig)
  # a.sort_by! { |word| word.size }
  # a # => ["fig", "pear", "apple"]
  # ```
  def sort_by!(&block : T -> _) : Array(T)
    sorted = map { |e| {e, yield(e)} }.sort! { |x, y| x[1] <=> y[1] }
    _self = self.snapshot
    # In case self is changed after the sort
    # we copy only the amount of elements that it
    # is know to be in both sorted and _self
    Math.min(_self.size, sorted.size).times do |i|
      _self.data[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  # Swaps the elements at *index0* and *index1* and returns `self`.
  # Raises an `IndexError` if either index is out of bounds.
  #
  # ```
  # a = ["first", "second", "third"]
  # a.swap(1, 2)  # => ["first", "third", "second"]
  # a             # => ["first", "third", "second"]
  # a.swap(0, -1) # => ["second", "third", "first"]
  # a             # => ["second", "third", "first"]
  # a.swap(2, 3)  # => raises "Index out of bounds (IndexError)"
  # ```
  def swap(index0, index1) : Array(T)
    _self = self.snapshot
    index0 += _self.size if index0 < 0
    index1 += _self.size if index1 < 0

    unless (0 <= index0 < _self.size) && (0 <= index1 < _self.size)
      raise IndexError.new
    end

    ptr = _self.data
    ptr[index0], ptr[index1] = ptr[index1], ptr[index0]

    self
  end

  def to_a
    self
  end

  def to_s(io : IO) : Nil
    executed = exec_recursive(:to_s) do
      io << '['
      join ", ", io, &.inspect(io)
      io << ']'
    end
    io << "[...]" unless executed
  end

  def pretty_print(pp) : Nil
    executed = exec_recursive(:pretty_print) do
      pp.list("[", self, "]")
    end
    pp.text "[...]" unless executed
  end

  # Returns a pointer to the internal buffer where `self`'s elements are stored.
  #
  # This method is **unsafe** because it returns a pointer, and the pointed might eventually
  # not be that of `self` if the array grows and its internal buffer is reallocated.
  #
  # ```
  # ary = [1, 2, 3]
  # ary.to_unsafe[0] # => 1
  # ```
  def to_unsafe : Pointer(T)
    @buffer.data
  end

  # Assumes that `self` is an array of arrays and transposes the rows and columns.
  #
  # ```
  # a = [[:a, :b], [:c, :d], [:e, :f]]
  # a.transpose # => [[:a, :c, :e], [:b, :d, :f]]
  # a           # => [[:a, :b], [:c, :d], [:e, :f]]
  # ```
  def transpose
    return Array(Array(typeof(first.first))).new if empty?

    len = self[0].size
    (1...@size).each do |i|
      l = self[i].size
      raise IndexError.new if len != l
    end

    Array(Array(typeof(first.first))).new(len) do |i|
      Array(typeof(first.first)).new(@size) do |j|
        self[j][i]
      end
    end
  end

  # Returns a new `Array` by removing duplicate values in `self`.
  #
  # ```
  # a = ["a", "a", "b", "b", "c"]
  # a.uniq # => ["a", "b", "c"]
  # a      # => [ "a", "a", "b", "b", "c" ]
  # ```
  def uniq
    uniq &.itself
  end

  # Returns a new `Array` by removing duplicate values in `self`, using the block's
  # value for comparison.
  #
  # ```
  # a = [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # a.uniq { |s| s[0] } # => [{"student", "sam"}, {"teacher", "matz"}]
  # a                   # => [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # ```
  def uniq(&block : T -> _)
    _self = self.snapshot
    if _self.size <= 1
      Array.from_snapshot(_self)
    else
      hash = _self.to_lookup_hash { |elem| yield elem }
      hash.values
    end
  end

  # Removes duplicate elements from `self`. Returns `self`.
  #
  # ```
  # a = ["a", "a", "b", "b", "c"]
  # a.uniq! # => ["a", "b", "c"]
  # a       # => ["a", "b", "c"]
  # ```
  def uniq!
    uniq! &.itself
  end

  # Removes duplicate elements from `self`, using the block's value for comparison. Returns `self`.
  #
  # ```
  # a = [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # a.uniq! { |s| s[0] } # => [{"student", "sam"}, {"teacher", "matz"}]
  # a                    # => [{"student", "sam"}, {"teacher", "matz"}]
  # ```
  def uniq!
    _self = self.snapshot

    if _self.size <= 1
      return self
    end

    hash = _self.to_lookup_hash { |elem| yield elem }
    if _self.size == hash.size
      return self
    end

    old_size = _self.size
    new_size = hash.size
    removed = old_size - new_size
    return self if removed == 0

    ptr = _self.data
    # the hash will have less elements that the original capacity
    # of the buffer. And buffer can only grow.
    hash.each do |k, v|
      ptr.value = v
      ptr += 1
    end

    set_size_and_buffer(new_size, _self.buffer)

    self
  end

  # Prepend. Adds *obj* to the beginning of `self`, given that the type of the value is *T*
  # (which might be a single type or a union of types).
  # This method returns `self`, so several calls can be chained.
  # See `shift` for the opposite effect.
  #
  # ```
  # a = ["a", "b"]
  # a.unshift("c") # => ["c", "a", "b"]
  # a.unshift(1)   # Errors, because the array only accepts String.
  #
  # a = ["a", "b"] of (Int32 | String)
  # a.unshift("c") # => ["c", "a", "b"]
  # a.unshift(1)   # => [1, "c", "a", "b"]
  # ```
  def unshift(obj : T)
    insert 0, obj
  end

  # Prepend multiple values. The same as `unshift`, but takes an arbitrary number
  # of values to add to the array. Returns `self`.
  def unshift(*values : T)
    _self = self.snapshot

    new_size = _self.size + values.size
    new_buffer = _self.buffer.ensure_capacity(new_size)
    move_value = values.size
    new_buffer.data.move_to(new_buffer.data + move_value, _self.size)

    values.each_with_index do |value, i|
      new_buffer.data[i] = value
    end
    set_size_and_buffer new_size, new_buffer
    self
  end

  def update(index : Int)
    check_index_out_of_bounds index
    _self = self.snapshot
    index = _self.check_index_out_of_bounds index

    _self.data[index] = yield _self.data[index]
  end

  # :nodoc:
  def index(object, offset : Int = 0)
    # Optimize for the case of looking for a byte in a byte slice
    if T.is_a?(UInt8.class) &&
       (object.is_a?(UInt8) || (object.is_a?(Int) && 0 <= object < 256))
      return Slice.new(to_unsafe, size).fast_index(object, offset)
    end

    super
  end

  private class PermutationIterator(T)
    include Iterator(Array(T))

    @array : Array(T)
    @size : Int32
    @n : Int32
    @cycles : Array(Int32)
    @pool : Array(T)
    @stop : Bool
    @i : Int32
    @first : Bool
    @reuse : Array(T)?

    def initialize(@array : Array(T), @size, reuse)
      @n = @array.size
      @cycles = (@n - @size + 1..@n).to_a.reverse!
      @pool = @array.dup
      @stop = @size > @n
      @i = @size - 1
      @first = true

      if reuse
        if reuse.is_a?(Array)
          @reuse = reuse
        else
          @reuse = Array(T).new(@size)
        end
      end
    end

    def next
      return stop if @stop

      if @first
        @first = false
        return pool_slice(@pool, @size, @reuse)
      end

      while @i >= 0
        ci = (@cycles[@i] -= 1)
        if ci == 0
          e = @pool[@i]
          (@i + 1).upto(@n - 1) { |j| @pool[j - 1] = @pool[j] }
          @pool[@n - 1] = e
          @cycles[@i] = @n - @i
        else
          @pool.swap @i, -ci
          value = pool_slice(@pool, @size, @reuse)
          @i = @size - 1
          return value
        end
        @i -= 1
      end

      @stop = true
      stop
    end
  end

  private class CombinationIterator(T)
    include Iterator(Array(T))

    @size : Int32
    @n : Int32
    @copy : Array(T)
    @pool : Array(T)
    @indices : Array(Int32)
    @stop : Bool
    @i : Int32
    @first : Bool
    @reuse : Array(T)?

    def initialize(array : Array(T), @size, reuse)
      @n = array.size
      @copy = array.dup
      @pool = array.dup
      @indices = (0...@size).to_a
      @stop = @size > @n
      @i = @size - 1
      @first = true

      if reuse
        if reuse.is_a?(Array)
          @reuse = reuse
        else
          @reuse = Array(T).new(@size)
        end
      end
    end

    def next
      return stop if @stop

      if @first
        @first = false
        return pool_slice(@pool, @size, @reuse)
      end

      while @i >= 0
        if @indices[@i] != @i + @n - @size
          @indices[@i] += 1
          @pool[@i] = @copy[@indices[@i]]

          (@i + 1).upto(@size - 1) do |j|
            @indices[j] = @indices[j - 1] + 1
            @pool[j] = @copy[@indices[j]]
          end

          value = pool_slice(@pool, @size, @reuse)
          @i = @size - 1
          return value
        end
        @i -= 1
      end

      @stop = true
      stop
    end
  end

  private class RepeatedCombinationIterator(T)
    include Iterator(Array(T))

    @size : Int32
    @n : Int32
    @copy : Array(T)
    @indices : Array(Int32)
    @pool : Array(T)
    @stop : Bool
    @i : Int32
    @first : Bool
    @reuse : Array(T)?

    def initialize(array : Array(T), @size, reuse)
      @n = array.size
      @copy = array.dup
      @indices = Array.new(@size, 0)
      @pool = @indices.map { |i| @copy[i] }
      @stop = @size > @n
      @i = @size - 1
      @first = true

      if reuse
        if reuse.is_a?(Array)
          @reuse = reuse
        else
          @reuse = Array(T).new(@size)
        end
      end
    end

    def next
      return stop if @stop

      if @first
        @first = false
        return pool_slice(@pool, @size, @reuse)
      end

      while @i >= 0
        if @indices[@i] != @n - 1
          ii = @indices[@i] + 1
          tmp = @copy[ii]
          @indices.fill(@i, @size - @i) { ii }
          @pool.fill(@i, @size - @i) { tmp }

          value = pool_slice(@pool, @size, @reuse)
          @i = @size - 1
          return value
        end
        @i -= 1
      end

      @stop = true
      stop
    end
  end

  private struct FlattenHelper(T)
    def self.flatten(ary)
      result = [] of T
      flatten ary, result
      result
    end

    def self.flatten(ary : Array, result)
      ary.each do |elem|
        flatten elem, result
      end
    end

    def self.flatten(iter : Iterator, result)
      iter.each do |elem|
        flatten elem, result
      end
    end

    def self.flatten(other : T, result)
      result << other
    end

    def self.element_type(ary)
      case ary
      when Array
        element_type(ary.first)
      when Iterator
        element_type(ary.next)
      else
        ary
      end
    end
  end
end

private def pool_slice(pool, size, reuse)
  if reuse
    reuse.clear
    size.times { |i| reuse << pool[i] }
    reuse
  else
    pool[0, size]
  end
end
