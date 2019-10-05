module Crystal::Profiling
  @@stop = false
  @@profile_finished = false
  @@lock = Mutex.new

  @@profiling_file : IO?

  FILE_PATH = ENV.fetch("CRYSTAL_PROFILING_FILE") { "#{File.basename(PROGRAM_NAME)}.prom" }
  INTERVAL  = ENV.fetch("CRYSTAL_PROFILING_INTERVAL") { "0.5" }.to_f

  def self.profiling_file
    @@profiling_file ||= open_profiling_file
  end

  def self.open_profiling_file(file_path : Path | String = FILE_PATH)
    @@profiling_file = File.new(file_path, mode: "w")
  end

  def self.start(file_path : Path | String = FILE_PATH, interval = INTERVAL)
    profiling_file = open_profiling_file(file_path)

    Thread.new do
      while !@@stop
        emit_all(profiling_file, nil, Time.local.to_unix)
        sleep interval
      end

      profiling_file.puts
      profiling_file.close

      @@profile_finished = true
    end
  end

  def self.stop
    @@stop = true

    while !@@profile_finished
      Intrinsics.pause
    end
  end

  def self.debug(description, file = __FILE__, line = __LINE__)
    Crystal::Profiling.emit_all(profiling_file, {location: "#{file}:#{line}", description: description}, Time.local.to_unix)
  end

  def self.emit_all(io, attributes = nil, timestamp = nil)
    @@lock.synchronize do
      unsync_emit_all(io, attributes, timestamp)
    end
  end

  def self.unsync_emit_all(io, attributes = nil, timestamp = nil)
    emit_gc_prof_stats(profiling_file, attributes, timestamp)
    emit_fibers_stats(profiling_file, attributes, timestamp)
  end

  def self.emit_gc_prof_stats(io, attributes = nil, timestamp = nil)
    s = GC.prof_stats

    emit_metric_value io, "gc_prof_stats_heap_size", s.heap_size, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_free_bytes", s.free_bytes, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_unmapped_bytes", s.unmapped_bytes, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_bytes_since_gc", s.bytes_since_gc, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_non_gc_bytes", s.non_gc_bytes, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_gc_no", s.gc_no, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_markers_m1", s.markers_m1, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_bytes_reclaimed_since_gc", s.bytes_reclaimed_since_gc, attributes, timestamp
    emit_metric_value io, "gc_prof_stats_reclaimed_bytes_before_gc", s.reclaimed_bytes_before_gc, attributes, timestamp
  end

  def self.emit_fibers_stats(io, attributes = nil, timestamp = nil)
    running = 0
    resumable = 0
    dead = 0

    Fiber.unsafe_each do |f|
      if f.dead?
        dead += 1
      elsif f.running?
        running += 1
      elsif f.resumable?
        resumable += 1
      end
    end

    emit_metric_value io, "fibers", running, merge_attributes(attributes, {state: "running"}), timestamp
    emit_metric_value io, "fibers", resumable, merge_attributes(attributes, {state: "resumable"}), timestamp
    emit_metric_value io, "fibers", dead, merge_attributes(attributes, {state: "dead"}), timestamp
  end

  def self.emit_metric_value(io, name, value, attributes, timestamp)
    io << name
    emit_metric_attibutes(io, attributes) if attributes
    io << ' ' << value
    io << ' ' << timestamp if timestamp
    io << '\n'
    io.flush
  end

  def self.emit_metric_attibutes(io, attributes)
    io << "{"
    first = true
    attributes.each do |key, value|
      io << ", " unless first
      first = false

      io << key << '='

      case value
      when String
        value.inspect(io)
      else
        io << '"' << value << '"'
      end
    end
    io << "}"
  end

  def self.merge_attributes(attr1, attr2)
    if attr1 && attr2
      attr1.merge(attr2)
    else
      attr1 || attr2
    end
  end
end
