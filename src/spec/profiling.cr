require "crystal/profiling"

Spec.after_suite do
  Crystal::Profiling.profiling_file.puts
  Crystal::Profiling.profiling_file.close
end

class Spec::RootContext
  def report(kind, full_description, file, line, elapsed = nil, ex = nil)
    Crystal::Profiling.emit_all(Crystal::Profiling.profiling_file, {location: "#{file}:#{line}", description: full_description}, Time.local.to_unix)
    previous_def
  end
end
