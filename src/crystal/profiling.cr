module Crystal::Profiling
  @@stop = false
  @@profile_finished = false

  FILE_PATH = ENV.fetch("CRYSTAL_PROFILING_FILE") { "crystal.prom" }
  INTERVAL  = ENV.fetch("CRYSTAL_PROFILING_INTERVAL") { "0.1" }.to_f

  def self.start(file_path : Path | String = FILE_PATH, interval = INTERVAL)
    profiling_file = File.new(file_path, mode: "w")

    Thread.new do
      while !@@stop
        emit_gc(profiling_file)
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

  def self.emit_gc(io)
    s = GC.prof_stats
    io <<
      "GC.prof_stats{heap_size=\"#{s.heap_size}\", " <<
      "free_bytes=\"#{s.free_bytes}\", " <<
      "unmapped_bytes=\"#{s.unmapped_bytes}\", " <<
      "bytes_since_gc=\"#{s.bytes_since_gc}\", " <<
      "bytes_before_gc=\"#{s.bytes_before_gc}\", " <<
      "non_gc_bytes=\"#{s.non_gc_bytes}\", " <<
      "gc_no=\"#{s.gc_no}\", " <<
      "markers_m1=\"#{s.markers_m1}\", " <<
      "bytes_reclaimed_since_gc=\"#{s.bytes_reclaimed_since_gc}\", " <<
      "reclaimed_bytes_before_gc=\"#{s.reclaimed_bytes_before_gc}\"} " <<
      "#{Time.local.to_unix}\n"
    io.flush
  end
end
