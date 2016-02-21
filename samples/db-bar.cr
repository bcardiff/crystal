# custom type example
require "db"

class Bar
end

class BarDriver < DB::Driver
  def build_connection(db : DB::Database) : DB::Connection
    BarConnection.new(db)
  end

  class BarConnection < DB::Connection
    def initialize(db)
      super(db)
    end

    def build_statement(query)
      BarStatement.new(self)
    end

    def last_insert_id : Int64
      0
    end
  end

  class BarStatement < DB::Statement
    protected def perform_query(args : Slice(T))
      BarResultSet.new self, args
    end

    protected def perform_exec(args : Slice(T))
      DB::ExecResult.new 0, 0
    end
  end

  class BarResultSet < DB::ResultSet
    def initialize(statement, @args)
      super(statement)
      @has_next = true
    end

    def move_next
      if @has_next
        @has_next = false
        return true
      else
        return false
      end
    end

    def column_count
      1
    end

    def column_name(index)
      "c0"
    end

    def column_type(index : Int32)
      Bar
    end

    def read?(t : Nil.class)
      nil
    end

    def read?(t : String.class)
      ""
    end

    def read?(t : Int32.class)
      0i32
    end

    def read?(t : Int64.class)
      0i64
    end

    def read?(t : Float32.class)
      0f32
    end

    def read?(t : Float64.class)
      0f64
    end

    def read?(t : Slice(UInt8).class)
      Slice(UInt8).new(0)
    end

    # Implement Bar type
    def read?(t : Bar.class)
      if @args.size > 0 && (a = @args[0]).is_a?(Bar)
        a
      else
        Bar.new
      end
    end

    def read(t : Bar.class) : Bar
      read?(Bar).not_nil!
    end
    #
  end
end

DB.register_driver "bar", BarDriver

DB.open "bar://a" do |db|
  db.query("...") do |rs|
    rs.each do
      pp rs.read(Bar)
      pp rs.read(Nil)
      pp rs.read(Int32)
      pp rs.read(Float32)
    end
  end

  f = Bar.new
  pp f
  db.query("...", f) do |rs|
    pp rs.read(Bar)
  end

  pp db.scalar("...", f)
end
