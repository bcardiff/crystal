require "crystal/profiling"

Crystal::Profiling.start

at_exit { Crystal::Profiling.stop }
