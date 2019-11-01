# Source of libtsxlocks.a https://github.com/andikleen/tsx-tools
@[Link(ldflags: "#{__DIR__}/../../ext/libtsxlocks.a")]
lib LibTSX
  # fun spin_init_hle(lock : UInt32*)
  fun spin_lock_hle(lock : UInt32*)
  fun spin_unlock_hle(lock : UInt32*)

  # fun spin_init_rtm(lock : UInt32*)
  fun spin_lock_rtm(lock : UInt32*)
  fun spin_unlock_rtm(lock : UInt32*)
end
