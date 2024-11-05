/* Debug Mode state tracking */

// TODO: note I did NOT implement the following requirement from the Sdext spec
// for enter_debug_mode:
//
// "If the current instruction can be partially executed and should be restarted to complete,
// then the relevant state for that is updated. E.g. if a halt occurs during a partially
// executed vector instruction, then vstart is updated, and dpc is updated to the address
// of the partially executed instruction. This is analogous to how vector instructions
// behave for exceptions."

function enter_debug_mode_with_next_pc_default(cause : DebugModeCause, next_pc : xlenbits) -> unit = {
  assert(cause != DEBUG_MODE_CAUSE_RESERVED_0 & cause != DEBUG_MODE_CAUSE_RESERVED_7);
  dcsr[CAUSE] = debugModeCauseBits(cause);
  dcsr[V]     = 0b0; // TODO check if we should prepare for H-mode.
  dcsr[PRV]   = match (extensionEnabled(Ext_H), true_cur_privilege) {
    (false, User)       => 0b00,
    (false, Supervisor) => 0b01,
    (false, Machine)    => 0b11,
    _ => internal_error(__FILE__, __LINE__, "Invalid combination of extensionEnabled(Ext_H) and true_cur_privilege")
  };
  let _ = set_dpc(next_pc);
  debug_mode_active = true;
}

function enter_debug_mode_default(cause : DebugModeCause) -> unit = {
  if cause == DEBUG_MODE_CAUSE_EBREAK | cause == DEBUG_MODE_CAUSE_TRIGGER then
    enter_debug_mode_with_next_pc(cause, get_arch_pc())
  else
    enter_debug_mode_with_next_pc(cause, get_next_pc())
}

val leave_debug_mode_default : unit -> unit
function leave_debug_mode_default() = {
  let restoredPriv : Privilege = match (extensionEnabled(Ext_H), dcsr.V(), dcsr.PRV()) {
    (false, 0b0, 0b00) => User,
    (false, 0b0, 0b01) => Supervisor,
    (false, 0b0, 0b11) => Machine ,
    _ => internal_error(__FILE__, __LINE__, "Invalid combination of extensionEnabled(Ext_H), dcsr.v and dcsr.prv")
  };
  set_cur_privilege(restoredPriv);
  if true_cur_privilege != Machine then mstatus[MPRV] = 0b0; // TODO check why we don't have to do anything with mstatus[MPRV] on debug mode entry
  debug_mode_active = false;
  set_next_pc(get_dpc());
}

function dispatchDebugEntry_default() -> option((Retired, bool)) = {
  let result = if debug_entry then {
    if   get_config_print_instr()
    then print_instr("Handling debug entry");
    enter_debug_mode(debugModeCauseBits(debug_entry_cause));
    Some(RETIRE_FAIL, false)
  } else if pending_debug_entry_by_step & not(debug_mode_active) then {
    enter_debug_mode(DEBUG_MODE_CAUSE_SINGLE_STEP);
    Some(RETIRE_FAIL, false)
  } else {
    None()
  };
  pending_debug_entry_by_step = false;
  result
}

function clause is_CSR_defined (0x7b0) = debug_mode_active // dcsr
function clause is_CSR_defined (0x7b1) = debug_mode_active // dpc
function clause is_CSR_defined (0x7b2) = debug_mode_active // dscratch0
function clause is_CSR_defined (0x7b3) = debug_mode_active // dscratch1
