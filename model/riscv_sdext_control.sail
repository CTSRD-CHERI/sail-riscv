function enter_debug_mode_with_next_pc(cause: DebugModeCause, next_pc: xlenbits) -> unit =
  enter_debug_mode_with_next_pc_default(cause, next_pc)

function enter_debug_mode(cause: DebugModeCause) -> unit =
  enter_debug_mode_default(cause)

function leave_debug_mode() -> unit =
  leave_debug_mode_default()

function dispatchDebugEntry() -> option((Retired, bool)) =
  dispatchDebugEntry_default()
