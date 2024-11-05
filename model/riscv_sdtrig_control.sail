function debugModeTriggerActionPriority(act : DebugModeTrigAction) -> range(0, 2) = { // TODO shorten name
  match act {
    DEBUG_TRIG_ENTER_DEBUG_MODE => 2, // Highest
    DEBUG_TRIG_RAISE_BREAKPOINT_EXCEPTION => 1,
    _ => 0
  }
}

enum MatchOptionsMcontrol6 = {
  EQUAL,
  NAPOT_EQUAL,
  GE,
  LT,
  MASK_LOW,        // Not supported currently.
  MASK_HIGH,       // Not supported currently.
  NOT_EQUAL,       // Not supported currently.
  NOT_NAPOT_EQUAL, // Not supported currently.
  NOT_MASK_LOW,    // Not supported currently.
  NOT_MASK_HIGH    // Not supported currently.
}

mapping matchOptionsMcontrolBits : MatchOptionsMcontrol6 <-> bits(4) = {
  EQUAL           <-> 0b0000,
  NAPOT_EQUAL     <-> 0b0001,
  GE              <-> 0b0010,
  LT              <-> 0b0011,
  MASK_LOW        <-> 0b0100,
  MASK_HIGH       <-> 0b0101,
  NOT_EQUAL       <-> 0b1000,
  NOT_NAPOT_EQUAL <-> 0b1001,
  NOT_MASK_LOW    <-> 0b1100,
  NOT_MASK_HIGH   <-> 0b1101
}

val find_least_significant_zero  : forall 'n. (bits('n)) -> option(range(0, 'n - 1))
function find_least_significant_zero (bv) = {
  foreach (i from 0 to (sizeof('n) - 1)) { if (bv[i] == bitzero) then return Some(i) };
  None()
}

val set_all_hit_bits_and_return_trig_actions :  list((range(0,5), DebugModeTrigAction)) -> list(DebugModeTrigAction)
function set_all_hit_bits_and_return_trig_actions(l) = {
  match l {
    [||] => [||],
    (i, dt) :: rest => {
      record_trigger_hit(i);
      dt :: set_all_hit_bits_and_return_trig_actions(rest)
    }
  }
}

enum Addr_Check_Type = {Load_Addr, Store_Addr, Exec_Addr, AMO_Addr, CBO_Addr}

mapping addr_check_type_to_string : Addr_Check_Type <-> string = {
  Load_Addr  <-> "load address",
  Store_Addr <-> "store address",
  Exec_Addr  <-> "PC address",
  AMO_Addr   <-> "AMO address",
  CBO_Addr   <-> "CBO address"
}

function address_trigger_is_enabled(td : Mcontrol6, addr_ct : Addr_Check_Type) -> bool = {
  assert (not(debug_mode_active));

  // true_cur_privilege is not used because we cannot get here in debug mode.
  let privilege_enabled : bool = match cur_privilege() {
    // MTE == 0 disables triggers with action == 0 in M-mode.
    Machine    => td[M] == 0b1 & not(tcontrol[MTE] == 0b0 & td[ACTION] == 0b0000),
    Supervisor => td[S] == 0b1,
    User       => td[U] == 0b1,
  };

  let type_enabled : bool = match addr_ct {
    Exec_Addr  => td[EXECUTE] == 0b1,
    Store_Addr => td[STORE] == 0b1,
    CBO_Addr   => td[STORE] == 0b1 & td[SIZE] == 0b000,
    Load_Addr  => td[LOAD] == 0b1,
    AMO_Addr   => td[LOAD] == 0b1 | td[STORE] == 0b1,
  };

  privilege_enabled & type_enabled
}

val plat_cache_block_size_exp : unit -> range (0, 12) // Added header to simplify building w/o rewriting the cmake config

function get_debug_triggers(vaddr : xlenbits, addr_check_type : Addr_Check_Type) -> list(DebugModeTrigAction) = {
  var l : list((range(0, 5), DebugModeTrigAction)) = [||];
  foreach (active_trig from 0 to 3) { // Does not check for external triggers
    let td1 = Mk_Mcontrol6(read_tdata1_underlying(active_trig));
    let match_option = matchOptionsMcontrolBits(td1.MATCH());
    let action = debugModeTrigActionBits(zero_extend(td1.ACTION()));
    if action == DEBUG_TRIG_ENTER_DEBUG_MODE & get_DMODE(active_trig) != 0b1 then internal_error(__FILE__, __LINE__, "Tried to enter debug mode with invalid DMODE");
    let td2 = read_tdata2_underlying(active_trig);
    let mask : xlenbits = if addr_check_type == CBO_Addr then // Needed for triggering on a range for CBO
        ones() << plat_cache_block_size_exp()
      else
        ones();
    if address_trigger_is_enabled(td1, addr_check_type) then
      match match_option {
        EQUAL => { if (vaddr & mask) == (td2 & mask) then l = (active_trig, action) :: l },
        NAPOT_EQUAL => {
          match find_least_significant_zero(td2) {
            Some(i) => {
              let m : range(0, xlen) = xlen - 1 - i;
              if m <= 0 then internal_error(__FILE__, __LINE__, "Got invalid m = 0 in NAPOT_EQUAL " ^ addr_check_type_to_string(addr_check_type) ^ " trigger check, must be > 0");
              let tmp = xlen - m;
              if ((vaddr & mask) >> tmp) == ((td2 & mask) >> tmp) then l = (active_trig, action) :: l
            },
            _ => internal_error(__FILE__, __LINE__, "Found no 0 in NAPOT_EQUAL " ^ addr_check_type_to_string(addr_check_type) ^ " trigger check"),
          }
        },
        GE => if (vaddr & mask) >=_u (td2 & mask) then l = (active_trig, action) :: l,
        LT => if (vaddr & mask) <_u (td2 & mask) then l = (active_trig, action) :: l,
        mc => internal_error(__FILE__, __LINE__, "Match option " ^ BitStr(matchOptionsMcontrolBits(mc)) ^ " not supported currently. " ^ addr_check_type_to_string(addr_check_type) ^ " check"),
      };
  };
  set_all_hit_bits_and_return_trig_actions(l)
}

function highest_priority_debug_action(l : list(DebugModeTrigAction)) -> option(DebugModeTrigAction) = {
  match l {
    [||] => None(),
    [| act |] => Some(act),
    act :: rest => {
      match highest_priority_debug_action(rest) {
        None() => Some(act),
        Some(act_rest) => if debugModeTriggerActionPriority(act) > debugModeTriggerActionPriority(act_rest) then Some(act) else Some(act_rest)
      }
    }
  }
}

// TODO: Make this customisable.
function trigger_action_is_implemented(action : DebugModeTrigAction) -> bool = {
  match action {
    DEBUG_TRIG_RAISE_BREAKPOINT_EXCEPTION => true,
    DEBUG_TRIG_ENTER_DEBUG_MODE => true,
    DEBUG_TRIG_TRACE_ON => true,
    DEBUG_TRIG_TRACE_OFF => true,
    DEBUG_TRIG_TRACE_NOTIFY => true,
    _ => false
  }
}

function check_vaddr_for_sdtrig(vaddr : xlenbits, addr_check_type : Addr_Check_Type) -> option(Trigger_Reason) = {
  if not(haveSdtrig()) | debug_mode_active then return None(); // TODO check how to handle e.g. debug_entry, pending_debug_entry_by_step
  match highest_priority_debug_action(get_debug_triggers(vaddr, addr_check_type)) { // Note: this does not check external triggers
    Some(action) if trigger_action_is_implemented(action) => Some(struct { vaddr = vaddr, action = action }),
    _ => None()
  }
}

// Several forward declaration to simplify compilation (avoid editing the makefile)
val enter_debug_mode_with_next_pc : (DebugModeCause, xlenbits) -> unit
val enter_debug_mode : DebugModeCause -> unit
val set_mepc : xlenbits -> unit
val set_sepc : xlenbits -> unit
val set_uepc : xlenbits -> unit
val handle_mem_exception : (xlenbits, ExceptionType) -> unit

function check_for_external_sdtrig() -> unit = {
  foreach (active_trig from 4 to 5) { // Does not check for external triggers
    let td1 = Mk_Tmexttrigger(read_tdata1_underlying(active_trig));
    if (external_trigs_fired & td1.SELECT() [1 .. 0]) != 0b00 then record_trigger_hit(active_trig);
  }
}

function handle_debug_action(
    reason : Trigger_Reason,
    instruction_pc : xlenbits
  ) -> option(Retired) = {
  match reason.action {
    DEBUG_TRIG_ENTER_DEBUG_MODE => {
      if not(haveSdext()) then internal_error(__FILE__, __LINE__, "Tried to enter debug mode without Sdext"); // TODO, check if this maybe should just become a NOP?
      enter_debug_mode_with_next_pc(DEBUG_MODE_CAUSE_TRIGGER, instruction_pc);
      Some(RETIRE_DEBUG_TRIGGER)
    },
    DEBUG_TRIG_RAISE_BREAKPOINT_EXCEPTION => {
      handle_mem_exception(reason.vaddr, E_Breakpoint());
      Some(RETIRE_DEBUG_TRIGGER)
    },
    DEBUG_TRIG_TRACE_ON     => None(), // Valid, but currently has no effect.
    DEBUG_TRIG_TRACE_OFF    => None(), // Valid, but currently has no effect.
    DEBUG_TRIG_TRACE_NOTIFY => None(), // Valid, but currently has no effect.
    _ => internal_error(__FILE__, __LINE__, "Got trigger action " ^ BitStr(debugModeTrigActionBits(reason.action)) ^ " that is currently not supported")
  }
}

function check_and_handle_triggers(
  vaddr : xlenbits,
  instruction_pc : xlenbits,
  addr_check_type : Addr_Check_Type
) -> option(Retired) = {
  match check_vaddr_for_sdtrig(convertInvalidAddr(vaddr), addr_check_type) {
    Some(trigger_reason) => { handle_debug_action(trigger_reason, instruction_pc) },
    None() => None()
  }
}

function check_and_handle_pc_for_triggers(pc : xlenbits) -> option(Retired) = {
  check_and_handle_triggers(pc, pc, Exec_Addr)
}

function check_and_handle_amo_vaddr_for_triggers(vaddr : xlenbits, instruction_pc : xlenbits)   -> option(Retired) = {
  check_and_handle_triggers(vaddr, instruction_pc, AMO_Addr)
}

function check_and_handle_load_vaddr_for_triggers(vaddr : xlenbits, instruction_pc : xlenbits)   -> option(Retired) = {
  check_and_handle_triggers(vaddr, instruction_pc, Load_Addr)
}

function check_and_handle_store_vaddr_for_triggers(vaddr : xlenbits, instruction_pc : xlenbits)   -> option(Retired) = {
  check_and_handle_triggers(vaddr, instruction_pc, Store_Addr)
}

function check_and_handle_cbo_vaddr_for_triggers(vaddr : xlenbits, instruction_pc : xlenbits)   -> option(Retired) = {
  check_and_handle_triggers(vaddr, instruction_pc, CBO_Addr)
}
