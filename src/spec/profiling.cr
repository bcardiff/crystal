require "crystal/profiling"

CONTEXT_FILE = File.new("crystal_spec.prom", mode: "w")

Spec.before_suite do
  Crystal::Profiling.start
end

Spec.after_suite do
  Crystal::Profiling.stop
  CONTEXT_FILE.puts
  CONTEXT_FILE.close
end

class Spec::RootContext
  def report(kind, full_description, file, line, elapsed = nil, ex = nil)
    CONTEXT_FILE <<
      "spec.context{kind=\"#{kind}\", " <<
      "location=\"#{file}:#{line}\", " <<
      "description=\"#{full_description.inspect}\"} " <<
      "#{Time.local.to_unix}\n"
    CONTEXT_FILE.flush

    Crystal::Profiling.emit_gc(CONTEXT_FILE)

    previous_def
  end
end
