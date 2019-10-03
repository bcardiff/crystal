module Crystal::Profiling
  @@stop = false
  @@profile_finished = false

  FILE_PATH = ENV.fetch("CRYSTAL_PROFILING_FILE") { "#{File.basename(PROGRAM_NAME)}.prom" }
  INTERVAL  = ENV.fetch("CRYSTAL_PROFILING_INTERVAL") { "0.5" }.to_f

  def self.open_profiling_file(file_path : Path | String = FILE_PATH)
    File.new(file_path, mode: "w")
  end

  def self.start(file_path : Path | String = FILE_PATH, interval = INTERVAL)
    profiling_file = open_profiling_file(file_path)

    Thread.new do
      while !@@stop
        emit_gc_prof_stats(profiling_file, nil, Time.local.to_unix)
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
end
