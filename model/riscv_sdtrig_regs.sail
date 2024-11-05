// Note: everything in the Sdtrig implementation assumes that XLEN == MXLEN == DXLEN etc.

function legalize_tselect(o : xlenbits, v : xlenbits) -> xlenbits = {
  if unsigned(v) > 5 then zeros() else v
}

// This function is not needed but it simplifies code by types.
function example_read_tselect() -> range(0, 5) = {
  let v = unsigned(tselect);
  if v < 6 then v else internal_error(__FILE__, __LINE__, "Unsupported tselect " ^ dec_str(v))
}

bitfield Tdata1 : xlenbits = {
   TYPE  : xlen - 1 .. xlen - 4,
   DMODE : xlen - 5,
   DATA  : xlen - 6 .. 0
}

function tdata1_reset_value(v : xlenbits) -> bits(4) = {
  match unsigned(v) {
    x if x >= 0 & x <= 3 => 0x6,
    x if x == 4 | x == 5 => 0x7,
    _ => internal_error(__FILE__, __LINE__, "Unsupported value supplied " ^ dec_str(unsigned(v)))
  };
}

bitfield Mcontrol6 : xlenbits = {
  TYPE : xlen - 1 .. xlen - 4,
  DMODE : xlen - 5,
  UNCERTAIN : 26,
  HIT1 : 25,
  VS : 24,
  VU : 23,
  HIT0 : 22,
  SELECT : 21,
  reserved_0 : 20 .. 19,
  SIZE : 18 .. 16,
  ACTION : 15 .. 12,
  CHAIN : 11,
  MATCH : 10 .. 7,
  M : 6,
  UNCERTAINEN : 5,
  S : 4,
  U : 3,
  EXECUTE : 2,
  STORE : 1,
  LOAD : 0
}

// TODO: This is all implementation specific and needs to be customisable.
function legalize_mcontrol6(o : xlenbits, v : xlenbits) -> xlenbits = {
  let xlen = xlen;
  let v =  v[xlen - 1 .. xlen - 5] @ zeros(xlen - 32) @ v[26 .. 0]; // Forces reserved bits xlen - 6 .. 27 to be 0, works for RV32 and RV64
  let v = Mk_Mcontrol6(v);
  let v = update_reserved_0(v, zeros());  // Forces reserved bits 20 .. 19 to be 0
  let v = update_UNCERTAIN(v, 0b0);       // Not implemented. Hardcoding to 0
  let v = update_HIT1(v, 0b0);            // Not implemented. Hardcoding to 0. Note: hit0 is implemented
  let v = update_VS(v, 0b0);              // Not implemented. Hardcoding to 0
  let v = update_VU(v, 0b0);              // Not implemented. Hardcoding to 0
  let v = update_SELECT(v, 0b0);          // Implemented, but hardcoded to 0
  let v = update_SIZE(v, 0b000);          // Not implemented. Hardcoding to 0
  let act_new : bits(4) = match (v.DMODE(), v.ACTION()) {
    (0b0, 0b0001)             => 0b0000, // See clarification https://github.com/riscv/riscv-debug-spec/issues/995
    (_, x) if unsigned(x) > 4 => 0b0000, // Supports only 0-4. Resets to 0 if invalid value is written
    (_, x)                    => x
  };
  let v = update_ACTION(v, act_new);
  let v = update_CHAIN(v, 0b0); // Not implemented. Hardcoding to 0
  let v = update_MATCH(v, if unsigned(v.MATCH()) > 1 then 0b0000 else v.MATCH());
  let v = update_UNCERTAINEN(v, 0b0); // Not implemented. Hardcoding to 0
  v.bits
}



bitfield Tmexttrigger : xlenbits = {
  TYPE   : xlen - 1 .. xlen - 4,
  DMODE  : xlen - 5,
  HIT    : xlen - 6,
  INTCTL : 22,
  SELECT : 21 .. 6,
  ACTION : 5 .. 0
}

function legalize_tmexttrigger(o : xlenbits, v : xlenbits) -> xlenbits = {
  let xlen = xlen;
  let v =  v[xlen - 1 .. xlen - 6] @ zeros(xlen - 29) @ v[22 .. 0]; // Forces reserved bits xlen - 7 .. 23 to be 0, works for RV32 and RV64
  let v : Tmexttrigger = Mk_Tmexttrigger(v);
  let v = update_INTCTL(v, 0b0); // Not implemented. Hardcoding to 0
  let select_new : bits(16) = v.SELECT();
  let v = update_SELECT(v, if unsigned(select_new) < 4 then select_new else zeros()); // Current implementation only allows 0-3. Reset to 0 on illegal value
  let act_new : bits(6) = match (v.DMODE(), v.ACTION()) {
    (_, x) if unsigned(x) < 2 | unsigned(x) > 4 => 0b000010, // Current implementation allows only 2-4. Reset to 2 on illegal values
    (_, x)                                      => x
  };
  let v = update_ACTION(v, act_new);
  v.bits
}

bitfield Tinfo : xlenbits = {
  VERSION : 31 .. 24,
  INFO    : 15 .. 0
}

function legalize_tinfo(v : xlenbits) -> Tinfo = {
  [
    Mk_Tinfo(zeros()) with
    INFO = (if example_read_tselect() <= 3 then 0x0040 else 0x0080),
    VERSION = 0x01
  ]
}

bitfield Tcontrol : xlenbits = {
  MPTE : 7,
  MTE  : 3
}

function legalize_tcontrol(o : Tcontrol, v : xlenbits) -> Tcontrol = {
  let v = Mk_Tcontrol(v);
  [Mk_Tcontrol(zeros()) with MPTE = v.MPTE(), MTE = v.MTE()]
}

function legalize_tdata1(o : xlenbits, v : xlenbits) -> xlenbits = {
  let (update_tdata1, update_dmode) : (bool, bool) = match (debug_mode_active, true_cur_privilege, Mk_Tdata1(o).DMODE()) {
    (true, _, _ )     => (true, true),
    (_, Machine, 0b0) => (true, false),
    (_, _, _)         => (false, false)
  };
  if not(update_tdata1) then return o;
  let v = Mk_Tdata1(v);
  let v = update_DMODE(v, if update_dmode then v.DMODE() else Mk_Tdata1(o).DMODE());
  let v = update_TYPE(v, tdata1_reset_value(tselect));
  match v.TYPE() {
    0x6 => legalize_mcontrol6(o, v.bits),
    0x7 => legalize_tmexttrigger(o, v.bits),
    bs  => internal_error(__FILE__, __LINE__, "Currently unsupported TYPE " ^ BitStr(bs))
  }
}

// --------------------------------- Registers ---------------------------------

register tcontrol : Tcontrol // Trigger Control R/W

register tdata1_underlying : vector(6, dec, xlenbits)
function read_tdata1_underlying(active_trig : range(0, 5)) -> xlenbits = { tdata1_underlying[active_trig] }
function write_tdata1_underlying(active_trig : range(0, 5), v : xlenbits) -> unit = { tdata1_underlying[active_trig] = v }

// TODO: This is implementation specific. The Sdtrig spec is much more general.
function legalize_tdata2(o : xlenbits, v : xlenbits) -> xlenbits = {
  let update_tdata2 : bool = match (debug_mode_active, true_cur_privilege, Mk_Tdata1(read_tdata1_underlying(example_read_tselect())).DMODE()) {
    (true, _, _ )     => true,
    (_, Machine, 0b0) => true,
    (_, _, _)         => false
  };
  if not(update_tdata2) then return o;
  match example_read_tselect() {
    x if x >= 0 & x <= 3 => convertInvalidAddr(v),
    x if x == 4 | x == 5 => zeros()
  }
}

// From Sdtrig spec:
// "tdata2 is WARL and if bits maskmax6-1:0 are written with all ones then bit maskmax6-1 will be set to 0
// while the values of bitsmaskmax6-2:0 are UNSPECIFIED"
// Here we leave retain the UNSPECIFIED bits as all ones.
function legalize_tdata2_read(o : xlenbits, trig : range(0, 5)) -> xlenbits = {
  let xlen = xlen;
  let td1 = Mk_Mcontrol6(read_tdata1_underlying(trig));
  let maskmax6 = sys_maskmax6();
  assert(maskmax6 < xlen & maskmax6 > 1);
  match (td1.MATCH(), o[maskmax6 - 1 .. 0]) {
    (0b0001, bs) if bs == ones() => o[xlen - 1 .. maskmax6] @ zeros(1) @ o[maskmax6 - 2 .. 0],
    (_, _) => o
  }
}

// TODO: Configurable tselect values. Currently we only allow 0-5.
register tdata2_underlying : vector(6, dec, xlenbits)
// tdata2 is legalised on read rather than write to avoid state changes when switching between trigger match modes
function read_tdata2_underlying(active_trig : range(0, 5)) -> xlenbits = { legalize_tdata2_read(tdata2_underlying[active_trig], active_trig) }
function write_tdata2_underlying(active_trig : range(0, 5), v : xlenbits) -> unit = { tdata2_underlying[active_trig] = v }

function clause is_CSR_defined (0x5a8) = false        // Not implemented.
function clause is_CSR_defined (0x6a8) = false        // Not implemented.
function clause is_CSR_defined (0x7a0) = haveSdtrig() // tselect
function clause is_CSR_defined (0x7a1) = haveSdtrig() // tdata1
function clause is_CSR_defined (0x7a2) = haveSdtrig() // tdata2
function clause is_CSR_defined (0x7a3) = false        // Not implemented.
function clause is_CSR_defined (0x7a4) = haveSdtrig() // tinfo
function clause is_CSR_defined (0x7a5) = haveSdtrig() // tcontrol
function clause is_CSR_defined (0x7a8) = false        // Not implemented.
function clause is_CSR_defined (0x7aa) = false        // Not implemented.

// TODO: Currently only support 2 external triggers.
register external_trigs_fired : bits(2)

val set_external_trig_fired = {c : "set_external_trig"} : (bool, bool) -> unit

// Hit bits to be applied later in step if no CSR write was done to that tdata1 register
register hit_bits_to_set : vector(6, dec, bool)
// CSR write to tdata1 this step
register tdata1_write : bool

// --------------------------------- Helper functions ---------------------------------

function get_DMODE(i : range(0, 5)) -> bits(1) = {
  Mk_Tdata1(read_tdata1_underlying(i)).DMODE()
}

function set_hit_bit(i : range(0, 5), b : bits(1)) -> unit = {
  match i {
    x if x < 4 => {
      let o = read_tdata1_underlying(i);
      let v = update_HIT0(Mk_Mcontrol6(o), b);
      let v = legalize_mcontrol6(o, v.bits);
      write_tdata1_underlying(i, v)
    },
    _ => { // Triggered externally.
      let o = read_tdata1_underlying(i);
      let v = update_HIT(Mk_Tmexttrigger(o), b);
      let v = legalize_tmexttrigger(o, v.bits);
      write_tdata1_underlying(i, v)
    }
  }
}

function record_trigger_hit(i : range(0, 5)) -> unit = {
  hit_bits_to_set[i] = true;
}

function clear_trigger_hits() -> unit = {
  foreach (i from 0 to 5) {
    hit_bits_to_set[i] = false;
  }
}

// Update hit bits in each tdata1 register if there was
// no CSR write to that tdata1 register
function update_hit_bits() -> unit = {
  foreach (i from 0 to 5) {
    if hit_bits_to_set[i] & (not(tdata1_write) | example_read_tselect() != i) then set_hit_bit(i, 0b1);
  }
}

function update_mpte_mte_in_tcontrol() -> unit = {
  let v = update_MPTE(tcontrol, tcontrol.MTE());
  tcontrol = update_MTE(v, 0b0)
}

function restore_mte_in_tcontrol() -> unit = {
  tcontrol = update_MTE(tcontrol, tcontrol.MPTE())
}

// --------------------------------- Reset ---------------------------------

function reset_tselect() -> unit = { tselect = legalize_tselect(zeros(), zeros()) }
function reset_tcontrol() -> unit = { tcontrol = legalize_tcontrol(Mk_Tcontrol(zeros()), zeros()) }

// No function reset_tdata1: this is handled by reset_0x7a1 below.

function reset_0x7a1() -> unit = {
  foreach (i from 0 to 5) {
    let tdata1_type_reset_value = tdata1_reset_value(to_bits(xlen,i));
    let example_initial = tdata1_type_reset_value @ zeros(xlen - 4);
    match tdata1_type_reset_value {
        0x6 => write_tdata1_underlying(i, legalize_mcontrol6(zeros(), example_initial)),
        0x7 => write_tdata1_underlying(i, legalize_tmexttrigger(zeros(), example_initial)),
        bs  => internal_error(__FILE__, __LINE__, "Currently unsupported TYPE " ^ BitStr(bs)),
    }
  }
}

function reset_external_trigs_fired() -> unit = { external_trigs_fired = 0b00 }

function reset_sdtrig_registers() -> unit = {
  reset_tselect();
  reset_tcontrol();
  reset_0x7a1();
  reset_external_trigs_fired()
}
