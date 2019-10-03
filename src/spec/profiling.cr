require "crystal/profiling"

CONTEXT_FILE = Crystal::Profiling.open_profiling_file

Spec.after_suite do
  CONTEXT_FILE.puts
  CONTEXT_FILE.close
end

class Spec::RootContext
  def report(kind, full_description, file, line, elapsed = nil, ex = nil)
    Crystal::Profiling.emit_gc_prof_stats(CONTEXT_FILE, {location: "#{file}:#{line}", description: full_description}, Time.local.to_unix)
    previous_def
  end
end
