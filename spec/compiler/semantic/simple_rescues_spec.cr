require "../../spec_helper"

private def assert_transform(from, to, flags = nil)
  program = Program.new
  program.flags = flags if flags
  from_nodes = Parser.parse(from)
  to_nodes = from_nodes.transform SimpleRescues.new
  to_nodes.to_s.strip.should eq(to.strip)
end

describe "Semantic: SimpleRescues" do
  it "can do noop" do
    assert_transform(
      <<-CR
      a = 1
      CR
    ,
      <<-CR
      a = 1
      CR
    )
  end

  it "ensures variables on rescue blocks" do
    assert_transform(
      <<-CR
      begin
        a = 1
      rescue
        a = 2
      end
      CR
    ,
      <<-CR
      begin
        a = 1
      rescue ___e1
        a = 2
      end
      CR
    )
  end

  it "ensures translate single type restrictions to conditionals" do
    assert_transform(
      <<-CR
      begin
        a = 1
      rescue e : A
        e.foo
        a = 2
      end
      CR
    ,
      <<-CR
      begin
        a = 1
      rescue e
        if e.is_a?(A)
          e.foo
          a = 2
        else
          ::raise(e)
        end
      end
      CR
    )
  end

  it "ensures translate multiple type restrictions to conditionals" do
    assert_transform(
      <<-CR
      begin
        a = 1
      rescue e : A | B
        e.foo
        a = 2
      end
      CR
    ,
      <<-CR
      begin
        a = 1
      rescue e
        if e.is_a?(A | B)
          e.foo
          a = 2
        else
          ::raise(e)
        end
      end
      CR
    )
  end

  it "ensures translate multiple rescues with type restrictions" do
    assert_transform(
      <<-CR
      begin
        lorem
      rescue a : A
        a.foo
      rescue b : B
        b.bar
      end
      CR
    ,
      <<-CR
      begin
        lorem
      rescue ___e1
        if (a = ___e1) && (a.is_a?(A))
          a.foo
        else
          if (b = ___e1) && (b.is_a?(B))
            b.bar
          else
            ::raise(___e1)
          end
        end
      end
      CR
    )
  end

  it "ensures translate multiple rescues with type some restrictions" do
    assert_transform(
      <<-CR
      begin
        lorem
      rescue a : A
        a.foo
      rescue b
        b.bar
      end
      CR
    ,
      <<-CR
      begin
        lorem
      rescue ___e1
        if (a = ___e1) && (a.is_a?(A))
          a.foo
        else
          b = ___e1
          b.bar
        end
      end
      CR
    )
  end
end
