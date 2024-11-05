/* Debug Mode state */

enum DebugModeCause = {
  DEBUG_MODE_CAUSE_RESERVED_0,
  DEBUG_MODE_CAUSE_EBREAK,
  DEBUG_MODE_CAUSE_TRIGGER,
  DEBUG_MODE_CAUSE_HALT_REQUEST,
  DEBUG_MODE_CAUSE_SINGLE_STEP,
  DEBUG_MODE_CAUSE_RESET_HALT_REQUEST,
  DEBUG_MODE_CAUSE_HALT_GROUP,
  DEBUG_MODE_CAUSE_RESERVED_7
}

mapping debugModeCauseBits : DebugModeCause <-> bits(3) = {
  DEBUG_MODE_CAUSE_RESERVED_0         <-> 0b000,
  DEBUG_MODE_CAUSE_EBREAK             <-> 0b001,
  DEBUG_MODE_CAUSE_TRIGGER            <-> 0b010,
  DEBUG_MODE_CAUSE_HALT_REQUEST       <-> 0b011,
  DEBUG_MODE_CAUSE_SINGLE_STEP        <-> 0b100,
  DEBUG_MODE_CAUSE_RESET_HALT_REQUEST <-> 0b101,
  DEBUG_MODE_CAUSE_HALT_GROUP         <-> 0b110,
  DEBUG_MODE_CAUSE_RESERVED_7         <-> 0b111,
}


/* debug processing state */

// Debug mode entry. If this is set, enter debug mode.
register debug_entry : bool
register debug_entry_cause : bits(3)

// Enter debug mode via single step mode
register pending_debug_entry_by_step : bool = false

bitfield Dcsr : bits(32) = {
  DEBUGVER : 31 .. 28,
  reserved_1 : 27 .. 18,
  EBREAKVS : 17,
  EBREAKVU : 16,
  EBREAKM : 15,
  reserved_0 : 14,
  EBREAKS : 13,
  EBREAKU : 12,
  STEPIE : 11,
  STOPCOUNT : 10,
  STOPTIME : 9,
  CAUSE : 8 .. 6,
  V : 5,
  MPRVEN : 4,
  NMIP : 3,
  STEP : 2,
  PRV : 1 .. 0
}

function sys_debugver() -> bits(4) = 0b0100 // Hardcoded for A71. TODO: configure from JSON?
function sys_hart_stepie_writable() -> bool = false
function sys_hart_stopcount_writable() -> bool = false
function sys_hart_stoptime_writable() -> bool = false
function sys_hart_mprven_writable() -> bool = true
function sys_hart_stopcount_reset_value() -> bits(1) = 0b0
function sys_hart_stoptime_reset_value() -> bits(1) = 0b0
function sys_hart_mprven_reset_value() -> bits(1) = 0b0
function sys_hart_prv_default_value() -> bits(2) = 0b00

// If true then control transfer functions are illegal in debug mode.
function debugIllegalCtrlTransferInstr() -> bool = true

function legalize_dcsr(o : Dcsr, v : bits(32)) -> Dcsr = {
  let v : Dcsr = Mk_Dcsr(v);
  let v = update_reserved_0(v, zeros());
  let v = update_reserved_1(v, zeros());
  let v = update_DEBUGVER(v, sys_debugver());
  let v = update_EBREAKVS(v, if extensionEnabled(Ext_H) then v.EBREAKVS() else 0b0);
  let v = update_EBREAKVU(v, if extensionEnabled(Ext_H) then v.EBREAKVU() else 0b0);
  let v = update_EBREAKS(v, if extensionEnabled(Ext_S) then v.EBREAKS() else 0b0);
  let v = update_EBREAKU(v, if extensionEnabled(Ext_U) then v.EBREAKU() else 0b0);
  let v = update_STEPIE(v, if sys_hart_stepie_writable() then v.STEPIE() else 0b0);
  let v = update_STOPCOUNT(v, if sys_hart_stopcount_writable() then v.STOPCOUNT() else sys_hart_stopcount_reset_value());
  let v = update_STOPTIME(v, if sys_hart_stoptime_writable() then v.STOPTIME() else sys_hart_stoptime_reset_value());
  let v = update_CAUSE(v, o.CAUSE()); // Note: CAUSE is read-only, updates surpressed
  let v = update_V(v, if extensionEnabled(Ext_H) then v.V() else 0b0);
  let v = update_MPRVEN(v, if sys_hart_mprven_writable() then v.MPRVEN() else sys_hart_mprven_reset_value());
  let v = update_NMIP(v, o.NMIP()); // Note: NMIP is read-only, updates surpressed
  let v = update_PRV(v, if have_privLevel(v[PRV]) then v[PRV] else sys_hart_prv_default_value());

  v
}

register dcsr      : Dcsr

function ignore_mprv_in_debug() -> bool = debug_mode_active & (dcsr.MPRVEN() == 0b0)
