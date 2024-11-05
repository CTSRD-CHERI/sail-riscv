/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Machine-mode and supervisor-mode state definitions. */

/* privilege level */

/* whether Sdtrig was enabled at boot */
val sys_enable_sdtrig = {c: "sys_enable_sdtrig", ocaml: "Platform.enable_sdtrig", _: "sys_enable_sdtrig"} : unit -> bool
function haveSdtrig() -> bool = sys_enable_sdtrig()

/* whether Sdext was enabled at boot */
val sys_enable_sdext = {c: "sys_enable_sdext", ocaml: "Platform.enable_sdext", _: "sys_enable_sdext"} : unit -> bool
function haveSdext() -> bool = sys_enable_sdext()

register debug_mode_active : bool

// The underlying privilege if we were not in debug mode.
register true_cur_privilege : Privilege

// The effective privilege taking debug mode into account, which executes
// with machine mode privileges.
function cur_privilege() -> Privilege =
  if debug_mode_active then Machine else true_cur_privilege

function set_cur_privilege(v : Privilege) -> unit = {
  true_cur_privilege = v;
}

/* current instruction bits, used for illegal instruction exceptions */

register cur_inst : xlenbits

/* State projections
 *
 * Some machine state is processed via projections from machine-mode views to
 * views from lower privilege levels.  So, for e.g. when mstatus is read from
 * lower privilege levels, we use 'lowering_' projections:
 *
 *   mstatus  ->  sstatus  ->  ustatus
 *
 * Similarly, when machine state is written from lower privileges, that state is
 * lifted into the appropriate value for the machine-mode state.
 *
 *   ustatus  ->  sstatus  ->  mstatus
 *
 * In addition, several fields in machine state registers are WARL or WLRL,
 * requiring that values written to the registers be legalized.  For each such
 * register, there will be an associated 'legalize_' function.  These functions
 * will need to be supplied externally, and will depend on the legal values
 * supported by a platform/implementation (or misa).  The legalize_ functions
 * generate a legal value from the current value and the written value.  In more
 * complex cases, they will also implicitly read the current values of misa,
 * mstatus, etc.
 *
 * Each register definition below is followed by custom projections
 * and choice of legalizations if needed.  For now, we typically
 * implement the simplest legalize_ alternatives.
 */


/* M-mode registers */

bitfield Misa : xlenbits = {
  MXL  : xlen - 1 .. xlen - 2,

  Z    : 25,
  Y    : 24,
  X    : 23,
  W    : 22,
  V    : 21,
  U    : 20,
  T    : 19,
  S    : 18,
  R    : 17,
  Q    : 16,
  P    : 15,
  O    : 14,
  N    : 13,
  M    : 12,
  L    : 11,
  K    : 10,
  J    : 9,
  I    : 8,
  H    : 7,
  G    : 6,
  F    : 5,
  E    : 4,
  D    : 3,
  C    : 2,
  B    : 1,
  A    : 0
}
register misa : Misa

/* whether misa is R/W */
val sys_enable_writable_misa = pure "sys_enable_writable_misa" : unit -> bool
/* whether misa.c was enabled at boot */
val sys_enable_rvc = pure "sys_enable_rvc" : unit -> bool
/* whether misa.{f,d} were enabled at boot */
val sys_enable_fdext = pure "sys_enable_fdext" : unit -> bool
/* whether Svinval was enabled at boot */
val sys_enable_svinval = pure "sys_enable_svinval" : unit -> bool
/* whether Zcb was enabled at boot */
val sys_enable_zcb = pure "sys_enable_zcb" : unit -> bool
/* whether zfinx was enabled at boot */
val sys_enable_zfinx = pure "sys_enable_zfinx" : unit -> bool
/* whether Zfh/Zfhmin was enabled at boot */
val sys_enable_zfh = pure "sys_enable_zfh" : unit -> bool
val sys_enable_zfhmin = pure "sys_enable_zfhmin" : unit -> bool
/* whether Zvfh/Zvfhmin was enabled at boot */
val sys_enable_zvfh = pure "sys_enable_zvfh" : unit -> bool
val sys_enable_zvfhmin = pure "sys_enable_zvfhmin" : unit -> bool
/* whether Zba was enabled at boot */
val sys_enable_zba = pure "sys_enable_zba" : unit -> bool
/* whether Zbb was enabled at boot */
val sys_enable_zbb = pure "sys_enable_zbb" : unit -> bool
/* whether Zbc was enabled at boot */
val sys_enable_zbc = pure "sys_enable_zbc" : unit -> bool
/* whether Zbs was enabled at boot */
val sys_enable_zbs = pure "sys_enable_zbs" : unit -> bool
/* whether the N extension was enabled at boot */
val sys_enable_next = pure "sys_enable_next" : unit -> bool
/* whether Zkn was enabled at boot */
val sys_enable_zkn = pure "sys_enable_zkn" : unit -> bool
/* whether Zks was enabled at boot */
val sys_enable_zks = pure "sys_enable_zks" : unit -> bool

/* Which HPM counters are supported (as a bit mask). Bits [2 .. 0] are ignored. */
// val sys_writable_hpm_counters = pure "sys_writable_hpm_counters" : unit -> bits(32)

// Force the set bits of mcountinhibit to 1
// val sys_force_countinhibit_bits = pure "sys_force_countinhibit_bits" : unit -> bits(32)

// val sys_hpmevent_writable_bits = pure "sys_hpmevent_writable_bits" : unit -> bits(64)
// val sys_medeleg_writable_bits = pure "sys_medeleg_writable_bits" : unit -> bits(64)
// val sys_mideleg_writable_bits = pure "sys_mideleg_writable_bits" : unit -> bits(64)
// val sys_xtvec_writable_bits = pure "sys_xtvec_writable_bits" : unit -> bits(64)
// val sys_xcause_bits = pure "sys_xcause_bits" : unit -> range(0, 64)
// TODO
function sys_writable_hpm_counters() -> bits(32) = ones()
function sys_force_countinhibit_bits() -> bits(32) = zeros()
function sys_hpmevent_writable_bits() -> bits(64) = ones()
function sys_medeleg_writable_bits() -> bits(64) = ones()
function sys_mideleg_writable_bits() -> bits(64) = ones()
function sys_xtvec_writable_bits() -> bits(64) = ones()
function sys_xcause_bits() -> range(0, 64) = 64

// Number of CLIC interrupts supported
// val sys_clic_num_interrupts = pure "sys_clic_num_interrupts" : unit -> range(32,4096)
// TODO
function sys_clic_num_interrupts() -> range(32, 4096) = 4096

// Number of CLICINTCTL bits implemented
// val sys_clicintctl_writable_bits = pure "sys_clicintctl_writable_bits" : unit -> range(0,8)
// TODO
function sys_clicintctl_writable_bits() -> range(0, 8) = 8

// TODO (CLIC): Ideally we need callbacks for the parameters in 8.4. Additional CLIC Parameters
//
// Name            Value Range                  Description
// ------------------------------------------------------------------------------------------
// CLICANDBASIC    0-1                          Implements CLINT mode also?
// CLICPRIVMODES   1-3                          Number privilege modes: 1=M, 2=M/U, 3=M/S/U
// CLICLEVELS      2-256                        Number of interrupt levels including 0
// CLICMAXID       12-4095                      Largest interrupt ID
// INTTHRESHBITS   1-8                          Number of bits implemented in {intthresh}.th
// CLICCFGMBITS    0-ceil(lg2(CLICPRIVMODES))   Number of bits implemented for cliccfg.nmbits
// CLICCFGLBITS    0-ceil(lg2(CLICLEVELS))      Number of bits implemented for cliccfg.nlbits
// CLICMTVECALIGN  >= 6                         Number of hardwired-zero least significant bits in mtvec address.


/* How many PMP entries are implemented. This must be 0, 16 or 64 (this is checked at runtime). */
val sys_pmp_count = pure "sys_pmp_count" : unit -> range(0, 64)
/* Which PMP entries are writable. This is a bitmask. 1 means writable, 0 means read-only zero. */
// val sys_pmp_writable = pure "sys_pmp_writable" : unit -> bits(64)
// TODO
function sys_pmp_writable() -> bits(64) = ones()
/* G parameter that specifies the PMP grain size. The grain size is 2^(G+2), e.g.
   G=0 -> 4 bytes, G=10 -> 4096 bytes. */
val sys_pmp_grain = pure "sys_pmp_grain" : unit -> range(0, 63)

/* Which HPM counters are supported (as a bit mask). Bits [2 .. 0] are ignored. */
val sys_writable_hpm_counters = pure "sys_writable_hpm_counters" : unit -> bits(32)

// Physical address size. This must be at least 12 so you can address one page.
// The minimum of 13 is due to https://github.com/rems-project/sail/issues/471
// val sys_pa_bits = "sys_pa_bits" : unit -> range(13, if xlen == 32 then 34 else 56)
// TODO
function sys_pa_bits() -> range(13, if xlen == 32 then 34 else 56) = if xlen == 32 then 34 else 56

// Address Space ID size (max 16 bits). Currently this must be at least 1 due to
// https://github.com/rems-project/sail/issues/471
// val sys_asid_bits = "sys_asid_bits" : unit -> range(1, if xlen == 32 then 9 else 16)
// TODO
function sys_asid_bits() -> range(1, if xlen == 32 then 9 else 16) = if xlen == 32 then 9 else 16

/* Which virtual addressing modes are supported. Note Sv57 is not implemented yet. */
val sys_enable_sv32 = "sys_enable_sv32" : unit -> bool
val sys_enable_sv39 = "sys_enable_sv39" : unit -> bool
val sys_enable_sv48 = "sys_enable_sv48" : unit -> bool
val sys_enable_sv57 = "sys_enable_sv57" : unit -> bool

val sys_enable_tlb = "sys_enable_tlb" : unit -> bool

val sys_enable_svnapot = "sys_enable_svnapot" : unit -> bool

/* whether misa.v was enabled at boot */
val sys_enable_vext = pure "sys_enable_vext" : unit -> bool

/* whether misa.b was enabled at boot */
val sys_enable_bext = pure "sys_enable_bext" : unit -> bool

// CBO extensions. Zicbop cannot be enabled/disabled because it has no effect
// at all on this model.
val sys_enable_zicbom = pure "sys_enable_zicbom" : unit -> bool
val sys_enable_zicboz = pure "sys_enable_zicboz" : unit -> bool


// maskmax6 value for Sdtrig
// val sys_maskmax6 = "sys_maskmax6" : unit -> range(0, 63)
function sys_maskmax6() -> range(0, 63) = 63

function legalize_misa(m : Misa, v : xlenbits) -> Misa = {
  let  v = Mk_Misa(v);
  /* Suppress updates to MISA if MISA is not writable or if by disabling C next PC would become misaligned or an extension vetoes */
  if   not(sys_enable_writable_misa()) | (v[C] == 0b0 & (nextPC[1] == bitone))
  then m
  else {
    // Suppress enabling C if it is not supported.
    let m = if not(sys_enable_rvc()) then m else [m with C = v[C]];
    /* Suppress updates to misa.{f,d} if disabled at boot */
    if   not(sys_enable_fdext())
    then m
    else [m with F = v[F], D = v[D] & v[F]]
  }
}

// Note the model doesn't support hypervisor mode yet.
enum clause extension = Ext_H
function clause extensionEnabled(Ext_H) = misa[H] == 0b1

enum clause extension = Ext_U
function clause extensionEnabled(Ext_U) = misa[U] == 0b1

enum clause extension = Ext_S
function clause extensionEnabled(Ext_S) = misa[S] == 0b1

// Svnapot depends on Sv39.
enum clause extension = Ext_Svnapot
function clause extensionEnabled(Ext_Svnapot) = sys_enable_svnapot() & sys_enable_sv39()

/* Hardware Performance Monitoring counters */
enum clause extension = Ext_Zihpm
function clause extensionEnabled(Ext_Zihpm) = true

/*
 * Illegal values legalized to least privileged mode supported.
 * Note: the only valid combinations of supported modes are M, M+U, M+S+U.
 */
function lowest_supported_privLevel() -> Privilege =
  if extensionEnabled(Ext_U) then User else Machine

function have_privLevel(priv : priv_level) -> bool =
  match priv {
    0b00 => extensionEnabled(Ext_U),
    0b01 => extensionEnabled(Ext_S),
    0b10 => false,
    0b11 => true,
  }

bitfield Mstatush : bits(32) = {
  MBE  : 5,
  SBE  : 4
}
register mstatush : Mstatush

bitfield Mstatus : xlenbits = {
  SD   : xlen - 1,

  // The MBE and SBE fields are in mstatus in RV64 and absent in RV32.
  // On RV32, they are in mstatush, which doesn't exist in RV64.  For now,
  // they are handled in an ad-hoc way.
  // MBE  : 37
  // SBE  : 36

  // The SXL and UXL fields don't exist on RV32, so they are modelled
  // via explicit getters and setters; see below.
  // SXL  : 35 .. 34,
  // UXL  : 33 .. 32,

  TSR  : 22,
  TW   : 21,
  TVM  : 20,
  MXR  : 19,
  SUM  : 18,
  MPRV : 17,

  XS   : 16 .. 15,
  FS   : 14 .. 13,

  MPP  : 12 .. 11,
  VS   : 10 .. 9,
  SPP  : 8,

  MPIE : 7,
  SPIE : 5,

  MIE  : 3,
  SIE  : 1,
}
register mstatus : Mstatus

val ignore_mprv_in_debug : unit -> bool // TODO: this is a redundant forward declaration.
                                        // Body is in riscv_sdext_regs.sail for now.
                                        // Needs to be reordered.

function effectivePrivilege(t : AccessType(ext_access_type), m : Mstatus, priv : Privilege) -> Privilege =
  if   t != Execute() & m[MPRV] == 0b1 & not(ignore_mprv_in_debug())
  then privLevel_of_bits(m[MPP])
  else priv

// This is used by CLIC's weird CSRs. Returns true if the current privilege
// mode is the same as the previous privilege mode (before a the last trap).
// In other words if you call this in a trap handler, it checks if we have
// just taken a horizontal interrupt.
function currentPrivilegeMatchesPrevious() -> bool =
  match cur_privilege() {
    Machine => mstatus[MPP] == 0b11,
    Supervisor => mstatus[SPP] == 0b1,
    User => true,
  }

function get_mstatus_SXL(m : Mstatus) -> arch_xlen = {
  if   xlen == 32
  then arch_to_bits(RV32)
  else m.bits[35 .. 34]
}

function set_mstatus_SXL(m : Mstatus, a : arch_xlen) -> Mstatus = {
  if   xlen == 32
  then m
  else {
    let m = vector_update_subrange(m.bits, 35, 34,  a);
    Mk_Mstatus(m)
  }
}

function get_mstatus_UXL(m : Mstatus) -> arch_xlen = {
  if   xlen == 32
  then arch_to_bits(RV32)
  else m.bits[33 .. 32]
}

function set_mstatus_UXL(m : Mstatus, a : arch_xlen) -> Mstatus = {
  if   xlen == 32
  then m
  else {
    let m = vector_update_subrange(m.bits, 33, 32,  a);
    Mk_Mstatus(m)
  }
}

// "xPP fields are WARL fields that can hold only privilege mode x and any
// implemented privilege mode lower than x."
// The specific WARL implementation here is to set illegal values to the lowest
// supported mode.
function legalize_mpp(mpp : bits(2)) -> bits(2) =
  if have_privLevel(mpp) then mpp else privLevel_to_bits(lowest_supported_privLevel())

// "If privilege mode x is not implemented, then xPP must be read-only 0."
function legalize_spp(spp : bits(1)) -> bits(1) =
  if extensionEnabled(Ext_S) then spp else 0b0

function legalize_mstatus(o : Mstatus, v : xlenbits) -> Mstatus = {
  /*
   * Populate all defined fields using the bits of v, stripping anything
   * that does not have a matching bitfield entry. All bits above 32 are handled
   * explicitly later.
   */
  let m : Mstatus = Mk_Mstatus(zero_extend(v[22 .. 7] @ 0b0 @ v[5 .. 3] @ 0b0 @ v[1 .. 0]));

  /* Legalize MPP */
  let m = [m with
    MPP = legalize_mpp(m[MPP]),
    SPP = legalize_spp(m[SPP]),
  ];

  /* We don't have any extension context yet. */
  let m = [m with XS = extStatus_to_bits(Off)];

  /* FS is WARL, and making FS writable can support the M-mode emulation of an FPU
   * to support code running in S/U-modes.  Spike does this, and for now, we match it,
   * but only if Zfinx isn't enabled.
   * FIXME: This should be made a platform parameter.
   */
  let m = if sys_enable_zfinx() then [m with FS = extStatus_to_bits(Off)] else m;
  let dirty = extStatus_of_bits(m[FS]) == Dirty | extStatus_of_bits(m[XS]) == Dirty |
              extStatus_of_bits(m[VS]) == Dirty;
  let m = [m with SD = bool_to_bits(dirty)];

  /* We don't support dynamic changes to SXL and UXL. */
  let m = set_mstatus_SXL(m, get_mstatus_SXL(o));
  let m = set_mstatus_UXL(m, get_mstatus_UXL(o));

  /* We don't currently support changing MBE and SBE. */
  let m = if xlen == 64 then {
             Mk_Mstatus([m.bits with 37 .. 36 = 0b00])
          } else m;

  if not(extensionEnabled(Ext_U)) then {
    let m = [m with MPRV = 0b0];
    m
  } else m
}

/* architecture and extension checks */

function cur_Architecture() -> Architecture = {
  let a : arch_xlen =
    match (cur_privilege()) {
      Machine    => misa[MXL],
      Supervisor => get_mstatus_SXL(mstatus),
      User       => get_mstatus_UXL(mstatus)
    };
  match architecture(a) {
    Some(a) => a,
    None()  => internal_error(__FILE__, __LINE__, "Invalid current architecture")
  }
}

function in32BitMode() -> bool = {
  cur_Architecture() == RV32
}

/* interrupt processing state */

bitfield Minterrupts : xlenbits = {
  MEI : 11, /* external interrupts */
  SEI : 9,

  MTI : 7,  /* timers interrupts */
  STI : 5,

  MSI : 3,  /* software interrupts */
  SSI : 1,
}
register mip     : Minterrupts /* Pending */
register mie     : Minterrupts /* Enabled */
register mideleg : Minterrupts /* Delegation to S-mode */

/* mseccfg */
register mseccfg : Seccfg = legalize_mseccfg(Mk_Seccfg(zeros()), zeros())

// Initialised to legal values in case some bits are hard-coded to 1.
register menvcfg : MEnvcfg = legalize_menvcfg(Mk_MEnvcfg(zeros()), mseccfg, zeros())
register senvcfg : SEnvcfg = legalize_senvcfg(Mk_SEnvcfg(zeros()), menvcfg, zeros())

// Non Maskable Interrupt. If this is set an NMI is taken.
register nmi_taken : bool
// When an NMI is taken this is copied to `mcause`.
register nmi_cause : exc_code
// NMI is pending. Sets dcsr.nmip
register nmi_pending : bool

function legalize_mip(o : Minterrupts, v : xlenbits) -> Minterrupts = {
  /* The only writable bits are the S-mode bits, and with the 'N'
   * extension, the U-mode bits. */
  let v = Mk_Minterrupts(v);

  [o with
    SEI = v[SEI],
    SSI = v[SSI],
    // STI is read only if Sstc is enabled and STCE is set (it is equal to stimecmp <= mtime).
    STI = if extensionEnabled(Ext_Sstc) & menvcfg[STCE] == 0b1 then o[STI] else v[STI],
  ]
}

function legalize_mie(o : Minterrupts, v : xlenbits) -> Minterrupts = {
  let v = Mk_Minterrupts(v);
  [o with
    MEI = v[MEI],
    MTI = v[MTI],
    MSI = v[MSI],
    SEI = v[SEI],
    STI = v[STI],
    SSI = v[SSI]
  ]
}

function legalize_mideleg(o : Minterrupts, v : xlenbits) -> Minterrupts = {
  Mk_Minterrupts(v & sys_mideleg_writable_bits()[xlen - 1 .. 0])
}

/* exception processing state */

bitfield Medeleg : xlenbits = {
  SAMO_Page_Fault   : 15,
  Load_Page_Fault   : 13,
  Fetch_Page_Fault  : 12,
  MEnvCall          : 11,
  SEnvCall          : 9,
  UEnvCall          : 8,
  SAMO_Access_Fault : 7,
  SAMO_Addr_Align   : 6,
  Load_Access_Fault : 5,
  Load_Addr_Align   : 4,
  Breakpoint        : 3,
  Illegal_Instr     : 2,
  Fetch_Access_Fault: 1,
  Fetch_Addr_Align  : 0
}
register medeleg : Medeleg  /* Delegation to S-mode */

function legalize_medeleg(o : Medeleg, v : xlenbits) -> Medeleg = {
  let m = Mk_Medeleg(v & sys_medeleg_writable_bits()[xlen - 1 .. 0]);

  /* M-EnvCalls delegation is not supported */
  [m with MEnvCall = 0b0]
}

/* registers for trap handling */

bitfield Mtvec : xlenbits = {
  Base    : xlen - 1 .. 2,
  // This field overlaps with Base and is used for CLIC.
  Submode : 5 .. 2,
  Mode    : 1 .. 0,
}
register mtvec : Mtvec  /* Trap Vector */

function legalize_tvec(o : Mtvec, v : xlenbits) -> Mtvec = {
  let mask = sys_xtvec_writable_bits()[xlen - 1 .. 0];
  let v = Mk_Mtvec((v & mask) | (o.bits & ~(mask)));
  match trapVectorMode_bits(v[Mode]) {
    TV_Direct => v,
    TV_Vector => v,
    TV_Smclic if extensionEnabled(Ext_Smclic) & v[Submode] == zeros() => v,
    // Reserved behaviour is implementation specific.
    _ => if extensionEnabled(Ext_Smclic)
         then [v with Mode = o[Mode], Submode = o[Submode]]
         else [v with Mode = o[Mode]],
  }
}

function inSmclicMode() -> bool =
  extensionEnabled(Ext_Smclic) & trapVectorMode_bits(mtvec[Mode]) == TV_Smclic & mtvec[Submode] == zeros()

// In CLIC mode, xtvec.mode and xtvec.submode in lower privilege modes are
// writeable but appear to be 11 and 0000 respectively when read or implicitly
// read in that mode.

// In CLINT mode, both bits of xtvec.mode are writeable in lower-privilege modes
// but xtvec.mode bit 1 appears to be 0 when read or implicitly read in that mode.
function read_stvec_utvec(xtvec : xlenbits) -> xlenbits =
  if inSmclicMode()
  then [xtvec with 5 .. 0 = 0b000011]
  else if extensionEnabled(Ext_Smclic)
  then [xtvec with 1 = bitzero]
  else xtvec


bitfield Mcause : xlenbits = {
  IsInterrupt : xlen - 1,
  Cause       : xlen - 2 .. 0,

  // CLIC-only fields.

  // Mirrors of xstatus.xpp/xpie. No state associated with this here.
  ClicXstatusXpp  : 29 .. 28,
  ClicXstatusXpie : 27,

  // There's a unique value for each mcause, scause for these bits.
  // All other fields are shared between all of them (or mirros of xstatus).
  // The values for mcause and scause are stored in separate variables.
  Xinhv           : 30,
  Xpil            : 23 .. 16,

  // CLIC only allows 12-bit execution code.
  ClicExcCode     : 11 .. 0,
}

register mcause : Mcause
register scause : Mcause

function legalize_cause(v : xlenbits) -> Mcause = {
  let cause_bits = sys_xcause_bits();
  assert(cause_bits <= xlen - 1);

  let m = Mk_Mcause(v);
  [m with Cause = if cause_bits == 0 then zeros()
                  else zero_extend(m[Cause][cause_bits - 1 .. 0])]
}


function get_xcause(priv : Privilege) -> Mcause = {
  if inSmclicMode() then {
    match priv {
      // The Xpp/Xpie fields mirror mstatus, so copy them into the result.
      // This means any code that reads these fields MUST use get_xcause.
      // If you only read other fields then it's ok to access xcause directly.
      Machine => [
        mcause with
        ClicXstatusXpp = mstatus[MPP],
        ClicXstatusXpie = mstatus[MPIE],
      ],
      Supervisor => [
        scause with
        ClicXstatusXpp = zero_extend(mstatus[SPP]),
        ClicXstatusXpie = mstatus[SPIE],
      ],
      User => internal_error(__FILE__, __LINE__, "N extension not supported"),
    }
  } else {
    match priv {
      Machine => mcause,
      Supervisor => scause,
      User => internal_error(__FILE__, __LINE__, "N extension not supported"),
    }
  }
}

function set_xcause(priv : Privilege, value : xlenbits) -> unit = {
  if inSmclicMode() then {
    let cause = Mk_Mcause(value);
    // Zero reserved fields. This is implementation defined behaviour.
    let cause = [Mk_Mcause(zeros()) with
      IsInterrupt = cause[IsInterrupt],
      ClicXstatusXpp = cause[ClicXstatusXpp],
      ClicXstatusXpie = cause[ClicXstatusXpie],
      Xinhv = cause[Xinhv],
      Xpil = cause[Xpil],
      ClicExcCode = cause[ClicExcCode],
    ];

    // Legalise Xpp.
    let cause = [cause with ClicXstatusXpp = match priv {
      Machine => legalize_mpp(cause[ClicXstatusXpp]),
      Supervisor => 0b0 @ legalize_spp(cause[ClicXstatusXpp][0..0]),
      User => internal_error(__FILE__, __LINE__, "N extension not supported"),
    }];

    match priv {
      Machine => {
        mcause = cause;
        // These fields are actually mirrors of mstatus, so update them in
        // mstatus.
        mstatus[MPP] = cause[ClicXstatusXpp];
        mstatus[MPIE] = cause[ClicXstatusXpie];
      },
      Supervisor => {
        scause = cause;
        // MPP is 2 bits but SPP is only 1 bit.
        mstatus[SPP] = cause[ClicXstatusXpp][0..0];
        mstatus[SPIE] = cause[ClicXstatusXpie];
      },
      User => internal_error(__FILE__, __LINE__, "N extension not supported"),
    }
  } else {
    let cause = legalize_cause(value);
    match priv {
      Machine => mcause = cause,
      Supervisor => scause = cause,
      User => internal_error(__FILE__, __LINE__, "N extension not supported"),
    }
  }
}

/* Interpreting the trap-vector address */
function tvec_addr(m : Mtvec, c : Mcause) -> option(xlenbits) = {
  let base : xlenbits = m[Base] @ 0b00;
  match trapVectorMode_bits(m[Mode]) {
    TV_Direct => Some(base),
    TV_Vector => if   c[IsInterrupt] == 0b1
                 then Some(base + (zero_extend(c[Cause]) << 2))
                 else Some(base),
    TV_Smclic => if inSmclicMode() then Some(base) else None(),
    TV_Reserved => None(),
  }
}

/* Exception PC */

register mepc : xlenbits

/* The xepc legalization zeroes xepc[1:0] when misa.C is hardwired to 0.
 * When misa.C is writable, it zeroes only xepc[0].
 */
function legalize_xepc(v : xlenbits) -> xlenbits = {
  // allow writing xepc[1] only if misa.C is enabled or could be enabled.
  if   sys_enable_rvc()
  then [v with 0 = bitzero]
  else [v with 1..0 = zeros()]
}

// Align value to min supported PC alignment. This is used to
// legalize xepc reads.
function align_pc(addr : xlenbits) -> xlenbits = {
  if misa[C] == 0b1
  then [addr with 0 = bitzero]
  else [addr with 1..0 = zeros()]
}

/* auxiliary exception registers */

register mtval    : xlenbits
register mscratch : xlenbits

/* counters */

bitfield Counteren : bits(32) = {
  HPM  : 31 .. 3,
  IR   : 2,
  TM   : 1,
  CY   : 0
}

register mcounteren : Counteren
register scounteren : Counteren

function legalize_mcounteren(c : Counteren, v : xlenbits) -> Counteren = {
  let supported_counters = sys_writable_hpm_counters()[31 .. 3] @ 0b111;
  Mk_Counteren(v[31 .. 0] & supported_counters)
}

function legalize_scounteren(c : Counteren, v : xlenbits) -> Counteren = {
  let supported_counters = sys_writable_hpm_counters()[31 .. 3] @ 0b111;
  Mk_Counteren(v[31 .. 0] & supported_counters)
}

bitfield Counterin : bits(32) = {
  HPM  : 31 .. 3,
  IR : 2,
  CY : 0
}
register mcountinhibit : Counterin

function get_countinhibit() -> Counterin = Mk_Counterin(mcountinhibit.bits | sys_force_countinhibit_bits())

function legalize_mcountinhibit(c : Counterin, v : xlenbits) -> Counterin = {
  // Note the 0 in 0b101 is because the mtimer counter can't be paused.
  let supported_counters = sys_writable_hpm_counters()[31 .. 3] @ 0b101;
  Mk_Counterin(v[31 .. 0] & supported_counters)
}

register mcycle : bits(64)
register mtime : bits(64)

/* minstret
 *
 * This model-internal register is the full 64 bit minstret counter,
 * regardless of xlen. For xlen=32, this will be split across minstret
 * and minstreth CSRs.
 * The spec says that minstret increments on instruction retires need to
 * occur before any explicit writes to instret.  However, in our
 * simulation loop, we need to execute an instruction to find out
 * whether it retired, and hence can only increment instret after
 * execution. To avoid doing this in the case minstret was explicitly
 * written to, we track whether it should increment in a separate
 * model-internal register. We keep track of any explicit CSR writes in
 * the registers below and apply them after incrementing.
 */
register minstret : bits(64)

/* Should minstret be incremented when the instruction is retired. */
register minstret_increment : bool

// If there's an explicit write to minstret(h) then it is stored here because
// it needs to be applied *after* the implicit increment due to instruction
// retirement.
register minstret_write : option(bits(xlen))
register minstreth_write : option(bits(32))

function update_minstret() -> unit = {
  // First increment minstret due to instruction retirement
  // if it was not disabled by mcountinhibit.IR.
  if minstret_increment then {
    minstret = minstret + 1;
  };

  // Then apply explicit writes to minstret (if any).
  match minstret_write {
    Some(v) => minstret = [minstret with (xlen - 1) .. 0 = v],
    None() => (),
  };
  match minstreth_write {
    Some(v) => minstret = [minstret with 63 .. 32 = v],
    None() => (),
  };
}

// HPM (Hardware Performance Monitoring) counters. The lowest three values are
// not used but they are defined for simplicity.
register mhpmcounter : vector(32, bits(64))

// HPM events selector. These control what the HPM counters measure. The lowest
// three values are not used but they are defined for simplicity.
register mhpmevent : vector(32, xlenbits)

// Valid HPM counter indices. The lowest three are used for mcycle, mtime and minstret.
type hpmidx = range(3, 31)

// Convert the lowest 5 bits of a CSR index to an hpmidx. Asserts if it is 0..2.
function hpmidx_from_bits(b : bits(5)) -> hpmidx = {
  let index = unsigned(b);
  assert(index >= 3, "unreachable HPM index");
  index
}

function legalize_hpmevent(v : xlenbits) -> xlenbits = {
  v & sys_hpmevent_writable_bits()[xlen - 1 .. 0]
}

function read_mhpmcounter(index : hpmidx) -> xlenbits = mhpmcounter[index][(xlen - 1) .. 0]
function read_mhpmcounterh(index : hpmidx) -> bits(32) = mhpmcounter[index][63 .. 32]
function read_mhpmevent(index : hpmidx) -> xlenbits = mhpmevent[index]

// Write the HPM CSRs. These return the new value of the CSR, for use in writeCSR.
function write_mhpmcounter(index : hpmidx, value : xlenbits) -> unit =
  if sys_writable_hpm_counters()[index] == bitone then mhpmcounter[index][(xlen - 1) .. 0] = value

function write_mhpmcounterh(index : hpmidx, value : bits(32)) -> unit =
  if sys_writable_hpm_counters()[index] == bitone then mhpmcounter[index][63 .. 32] = value

function write_mhpmevent(index : hpmidx, value : xlenbits) -> unit =
  if sys_writable_hpm_counters()[index] == bitone then mhpmevent[index] = legalize_hpmevent(value)

/* informational registers */
register mvendorid : bits(32)
register mimpid : xlenbits
register marchid : xlenbits
/* TODO: this should be readonly, and always 0 for now */
register mhartid : xlenbits
register mconfigptr : xlenbits

/* S-mode registers */

/* sstatus reveals a subset of mstatus */
bitfield Sstatus : xlenbits = {
  SD   : xlen - 1,
  // The UXL field does not exist on RV32, so we define an explicit
  // getter and setter below.
  // UXL  : 30 .. 29,
  MXR  : 19,
  SUM  : 18,
  XS   : 16 .. 15,
  FS   : 14 .. 13,
  VS   : 10 .. 9,
  SPP  : 8,
  SPIE : 5,
  SIE  : 1,
}
/* sstatus is a view of mstatus, so there is no register defined. */

function get_sstatus_UXL(s : Sstatus) -> arch_xlen = {
  let m = Mk_Mstatus(s.bits);
  get_mstatus_UXL(m)
}

function set_sstatus_UXL(s : Sstatus, a : arch_xlen) -> Sstatus = {
  let m = Mk_Mstatus(s.bits);
  let m = set_mstatus_UXL(m, a);
  Mk_Sstatus(m.bits)
}

function lower_mstatus(m : Mstatus) -> Sstatus = {
  let s = Mk_Sstatus(zeros());
  let s = [s with SD = m[SD]];
  let s = set_sstatus_UXL(s, get_mstatus_UXL(m));

  [s with
    MXR = m[MXR],
    SUM = m[SUM],
    XS = m[XS],
    FS = m[FS],
    VS = m[VS],
    SPP = m[SPP],
    SPIE = m[SPIE],
    SIE = m[SIE],
  ]
}

function lift_sstatus(m : Mstatus, s : Sstatus) -> Mstatus = {
  let dirty = extStatus_of_bits(s[FS]) == Dirty | extStatus_of_bits(s[XS]) == Dirty |
              extStatus_of_bits(s[VS]) == Dirty;

  [m with
    SD = bool_to_bits(dirty),
    MXR = s[MXR],
    SUM = s[SUM],
    XS = s[XS],
    FS = s[FS],
    VS = s[VS],
    SPP = s[SPP],
    SPIE = s[SPIE],
    SIE = s[SIE],
  ]
}

function legalize_sstatus(m : Mstatus, v : xlenbits) -> Mstatus = {
  legalize_mstatus(m, lift_sstatus(m, Mk_Sstatus(v)).bits)
}

function get_xstatus(priv : Privilege) -> xlenbits =
  match priv {
    Machine => mstatus.bits,
    Supervisor => lower_mstatus(mstatus).bits,
    User => internal_error(__FILE__, __LINE__, "N extension not supported"),
  }

function set_xstatus(priv : Privilege, xstatus : xlenbits) -> unit = {
  mstatus = match priv {
    Machine => legalize_mstatus(mstatus, xstatus),
    Supervisor => legalize_sstatus(mstatus, xstatus),
    User => internal_error(__FILE__, __LINE__, "N extension not supported"),
  };
}


bitfield Sinterrupts : xlenbits = {
  SEI : 9,  /* external interrupts */

  STI : 5,  /* timers interrupts */

  SSI : 1,  /* software interrupts */
}

/* Provides the sip read view of mip (m) as delegated by mideleg (d). */
function lower_mip(m : Minterrupts, d : Minterrupts) -> Sinterrupts = {
  let s : Sinterrupts = Mk_Sinterrupts(zeros());

  [s with
    SEI = m[SEI] & d[SEI],
    STI = m[STI] & d[STI],
    SSI = m[SSI] & d[SSI],
  ]
}

/* Provides the sie read view of mie (m) as delegated by mideleg (d). */
function lower_mie(m : Minterrupts, d : Minterrupts) -> Sinterrupts = {
  let s : Sinterrupts = Mk_Sinterrupts(zeros());

  [s with
    SEI = m[SEI] & d[SEI],
    STI = m[STI] & d[STI],
    SSI = m[SSI] & d[SSI],
  ]
}

/* Returns the new value of mip from the previous mip (o) and the written sip (s) as delegated by mideleg (d). */
function lift_sip(o : Minterrupts, d : Minterrupts, s : Sinterrupts) -> Minterrupts = {
  let m : Minterrupts = o;
  let m = if d[SSI] == 0b1 then [m with SSI = s[SSI]] else m;
  m
}

function legalize_sip(m : Minterrupts, d : Minterrupts, v : xlenbits) -> Minterrupts = {
  lift_sip(m, d, Mk_Sinterrupts(v))
}

/* Returns the new value of mie from the previous mie (o) and the written sie (s) as delegated by mideleg (d). */
function lift_sie(o : Minterrupts, d : Minterrupts, s : Sinterrupts) -> Minterrupts = {
  let m : Minterrupts = o;
  let m = if d[SEI] == 0b1 then [m with SEI = s[SEI]] else m;
  let m = if d[STI] == 0b1 then [m with STI = s[STI]] else m;
  let m = if d[SSI] == 0b1 then [m with SSI = s[SSI]] else m;
  m
}

function legalize_sie(m : Minterrupts, d : Minterrupts, v : xlenbits) -> Minterrupts = {
  lift_sie(m, d, Mk_Sinterrupts(v))
}


/* other non-VM related supervisor state */
register stvec    : Mtvec
register sscratch : xlenbits
register sepc     : xlenbits
register stval    : xlenbits

/*
 * S-mode address translation and protection (satp) layout.
 * The actual satp register is defined in an architecture-specific file.
 */

bitfield Satp64 : bits(64) = {
  Mode : 63 .. 60,
  Asid : 59 .. 44,
  PPN  : 43 .. 0
}

function legalize_satp64(a : Architecture, o : bits(64), v : bits(64)) -> bits(64) = {
  let s = Mk_Satp64(v);
  let supported : bool = match satpMode_of_bits(a, s[Mode]) {
    None()      => false,
    Some(Sbare) => true,
    Some(Sv32)  => false, // Sv32 is not legal on RV64.
    Some(Sv39)  => sys_enable_sv39(),
    Some(Sv48)  => sys_enable_sv48(),
    Some(Sv57)  => sys_enable_sv57() & false, // TODO: Sv57 not implemented in the model yet.
  };

  let s = [
    s with
    // If full 16-bit ASID is not supported then the high bits will be read only zero.
    Asid = zero_extend(s[Asid][sys_asid_bits() - 1 .. 0]),
    // Bits above the physically addressable memory are read only zero.
    PPN = zero_extend(s[PPN][sys_pa_bits() - pagesize_bits - 1 .. 0]),
  ];

  s.bits
}

bitfield Satp32 : bits(32) = {
  Mode : 31,
  Asid : 30 .. 22,
  PPN  : 21 .. 0
}

function legalize_satp32(a : Architecture, o : bits(32), v : bits(32)) -> bits(32) = {
  let s = Mk_Satp32(v);
  let supported : bool = match satpMode_of_bits(a, 0b000 @ s[Mode]) {
    None()      => false,
    Some(Sbare) => true,
    Some(Sv32)  => sys_enable_sv32(),
  };

  // The extra `min()`s are to handle Sv32 on RV64, which is not really properly
  // supported by this model anyway.

  let s = [
    s with
    // If full 16-bit ASID is not supported then the high bits will be read only zero.
    Asid = zero_extend(s[Asid][min(9, sys_asid_bits()) - 1 .. 0]),
    // Bits above the physically addressable memory are read only zero.
    PPN = zero_extend(s[PPN][min(34, sys_pa_bits()) - pagesize_bits - 1 .. 0]),
  ];

  s.bits
}

/* disabled trigger/debug module */
register tselect : xlenbits

/*
 * The seed CSR (entropy source)
 * ------------------------------------------------------------
 */

/* Valid return states for reading the seed CSR. */
enum seed_opst = {
  BIST, // Built-in-self-test. No randomness sampled.
  ES16, // Entropy-sample-16. Valid 16-bits of randomness sampled.
  WAIT, // Device still gathering entropy.
  DEAD  // Fatal device compromise. No randomness sampled.
}

/* Mapping of status codes and their actual encodings. */
mapping opst_code : seed_opst <-> bits(2) = {
  BIST <-> 0b00,
  WAIT <-> 0b01,
  ES16 <-> 0b10,
  DEAD <-> 0b11
}

/*
 * Entropy Source - Platform access to random bits.
 * WARNING: This function currently lacks a proper side-effect annotation.
 *          If you are using theorem prover tool flows, you
 *          may need to modify or stub out this function for now.
 * NOTE: This would be better placed in riscv_platform.sail, but that file
 *       appears _after_ this one in the compile order meaning the valspec
 *       for this function is unavailable when it's first encountered in
 *       read_seed_csr. Hence it appears here.
 */
val get_16_random_bits = impure {
    interpreter: "Platform.get_16_random_bits",
    c: "plat_get_16_random_bits",
    lem: "plat_get_16_random_bits"
} : unit -> bits(16)

/* Entropy source spec requires an Illegal opcode exception be raised if the
 * seed register is read without also being written. This function is only
 * called once we know the CSR is being written, and all other access control
 * checks have been done.
 */
function read_seed_csr() -> xlenbits = {
  let reserved_bits : bits(6) = 0b000000;
  let custom_bits : bits(8) = 0x00;
  let seed : bits(16) = get_16_random_bits();
  zero_extend(opst_code(ES16) @ reserved_bits @ custom_bits @ seed)
}

/* Writes to the seed CSR are ignored */
function write_seed_csr () -> xlenbits = zeros()

// Return whether or not FIOM is currently active, based on the current
// privilege and the menvcfg/senvcfg settings. This means that I/O fences
// imply memory fence.
function is_fiom_active() -> bool = {
  match cur_privilege() {
    Machine => false,
    Supervisor => menvcfg[FIOM] == 0b1,
    User => (menvcfg[FIOM] | senvcfg[FIOM]) == 0b1,
  }
}

/* vector csrs */
register vstart : bits(16) /* use the largest possible length of vstart */
register vl     : xlenbits

function get_vlenb() -> xlenbits = {
  to_bits(xlen, (2 ^ (get_vlen_pow()) / 8))
}

bitfield Vtype  : xlenbits = {
  vill      : xlen - 1,
  reserved  : xlen - 2 .. 8,
  vma       : 7,
  vta       : 6,
  vsew      : 5 .. 3,
  vlmul     : 2 .. 0
}
register vtype : Vtype

/* the dynamic selected element width (SEW) */
/* this returns the power of 2 for SEW */
val get_sew_pow : unit -> {3, 4, 5, 6}
function get_sew_pow() = {
  let SEW_pow : {3, 4, 5, 6} = match vtype[vsew] {
    0b000 => 3,
    0b001 => 4,
    0b010 => 5,
    0b011 => 6,
    _     => {assert(false, "invalid vsew field in vtype"); 0}
  };
  SEW_pow
}
/* this returns the actual value of SEW */
val get_sew : unit -> {8, 16, 32, 64}
function get_sew() = {
  match get_sew_pow() {
    3 => 8,
    4 => 16,
    5 => 32,
    6 => 64,
    _ => {internal_error(__FILE__, __LINE__, "invalid SEW"); 8}
  }
}
/* this returns the value of SEW in bytes */
val get_sew_bytes : unit -> {1, 2, 4, 8}
function get_sew_bytes() = {
  match get_sew_pow() {
    3 => 1,
    4 => 2,
    5 => 4,
    6 => 8,
    _ => {internal_error(__FILE__, __LINE__, "invalid SEW"); 1}
  }
}

/* the vector register group multiplier (LMUL) */
/* this returns the power of 2 for LMUL */
val get_lmul_pow : unit -> {-3, -2, -1, 0, 1, 2, 3}
function get_lmul_pow() = {
  match vtype[vlmul] {
    0b101 => -3,
    0b110 => -2,
    0b111 => -1,
    0b000 => 0,
    0b001 => 1,
    0b010 => 2,
    0b011 => 3,
    _     => {assert(false, "invalid vlmul field in vtype"); 0}
  }
}

enum agtype = { UNDISTURBED, AGNOSTIC }

val decode_agtype : bits(1) -> agtype
function decode_agtype(ag) = {
  match ag {
    0b0 => UNDISTURBED,
    0b1 => AGNOSTIC
  }
}

val get_vtype_vma : unit -> agtype
function get_vtype_vma() = decode_agtype(vtype[vma])

val get_vtype_vta : unit -> agtype
function get_vtype_vta() = decode_agtype(vtype[vta])

/* Sstc : Supervisor Timer Register */
register stimecmp : bits(64)
