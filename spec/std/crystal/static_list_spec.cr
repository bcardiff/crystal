require "spec"
require "crystal/static_list.cr"

private struct TestedObject
  include Crystal::StaticList::Node(self)

  property value : Int32

  def initialize(@value : Int32)
  end
end

private macro expect_order_by_next(*vars)
  {% sz = vars.size %}
  {% for var, index in vars %}
    {% if (index + 1) < sz %}
      {{ var.id }}.next.should eq({{ vars[(index + 1)].id }}.self_pointer)
    {% end %}
  {% end %}
end

private macro expect_order_by_prev(*vars)
  {% sz = vars.size %}
  {% for var, index in vars %}
    {% if (index + 1) < sz %}
      {{ var.id }}.prev.should eq({{ vars[(index + 1)].id }}.self_pointer)
    {% end %}
  {% end %}
end

describe Crystal::StaticList do
  describe "init" do
    it "should be called after allocated" do
      list = Crystal::StaticList(TestedObject).new
      list.init
    end
  end

  describe "empty?" do
    it "return true if there is no element in list" do
      list = Crystal::StaticList(TestedObject).new
      list.init
      list.empty?.should be_true
    end
  end

  describe "push" do
    it "append the node into the list" do
      list = Crystal::StaticList(TestedObject).new
      list.init

      x = TestedObject.new 0
      y = TestedObject.new 1
      z = TestedObject.new 2

      list.push x.self_pointer
      list.push y.self_pointer
      list.push z.self_pointer

      expect_order_by_next(list.@dummy_head, x, y, z, list.@dummy_head)
      expect_order_by_prev(list.@dummy_head, z, y, x, list.@dummy_head)
    end
  end

  describe "list_append_to" do
    it "append self list to the target list" do
      list1 = Crystal::StaticList(TestedObject).new
      list1.init

      list2 = Crystal::StaticList(TestedObject).new
      list2.init

      x = TestedObject.new 0
      y = TestedObject.new 1
      z = TestedObject.new 2
      w = TestedObject.new 3

      list1.push x.self_pointer
      list1.push y.self_pointer
      list1.push z.self_pointer

      list2.push w.self_pointer

      list1.list_append_to pointerof(list2)

      expect_order_by_next(list2.@dummy_head, w, x, y, z, list2.@dummy_head)
      expect_order_by_prev(list2.@dummy_head, z, y, x, w, list2.@dummy_head)
    end

    it "make self list empty after the operation" do
      list1 = Crystal::StaticList(TestedObject).new
      list1.init

      list2 = Crystal::StaticList(TestedObject).new
      list2.init

      x = TestedObject.new 0
      y = TestedObject.new 1
      z = TestedObject.new 2
      w = TestedObject.new 3

      list1.push x.self_pointer
      list1.push y.self_pointer
      list1.push z.self_pointer

      list2.push w.self_pointer

      list1.list_append_to pointerof(list2)
      list1.empty?.should be_true
    end

    it "does nothing if self list is empty" do
      list1 = Crystal::StaticList(TestedObject).new
      list1.init

      list2 = Crystal::StaticList(TestedObject).new
      list2.init

      x = TestedObject.new 0

      list2.push x.self_pointer

      list1.list_append_to pointerof(list2)

      list1.empty?.should be_true

      expect_order_by_next(list2.@dummy_head, x, list2.@dummy_head)
      expect_order_by_prev(list2.@dummy_head, x, list2.@dummy_head)
    end
  end

  describe "delete" do
    it "remove a node from list" do
      list = Crystal::StaticList(TestedObject).new
      list.init

      x = TestedObject.new 0
      y = TestedObject.new 1
      z = TestedObject.new 2

      list.push x.self_pointer
      list.push y.self_pointer
      list.push z.self_pointer

      list.delete y.self_pointer

      expect_order_by_next(list.@dummy_head, x, z, list.@dummy_head)
      expect_order_by_prev(list.@dummy_head, z, x, list.@dummy_head)
    end
  end

  describe "shift?" do
    it "remove and return the first element" do
      list = Crystal::StaticList(TestedObject).new
      list.init

      x = TestedObject.new 0
      y = TestedObject.new 1
      z = TestedObject.new 2

      list.push x.self_pointer
      list.push y.self_pointer
      list.push z.self_pointer

      obj = list.shift?

      typeof(obj).should eq(Pointer(TestedObject)?)

      obj.nil?.should be_false
      obj.not_nil!.should eq(x.self_pointer)

      expect_order_by_next(list.@dummy_head, y, z, list.@dummy_head)
      expect_order_by_prev(list.@dummy_head, z, y, list.@dummy_head)
    end

    it "return nil if list is empty" do
      list = Crystal::StaticList(TestedObject).new
      list.init

      obj = list.shift?

      obj.should be_nil
    end
  end

  it "does each" do
    list = Crystal::StaticList(TestedObject).new
    list.init

    x = TestedObject.new 1
    y = TestedObject.new 2
    z = TestedObject.new 4

    sum = 0

    list.push x.self_pointer
    list.push y.self_pointer
    list.push z.self_pointer

    list.each do |it|
      sum += it.value.value
    end

    sum.should eq(7)
  end
end
