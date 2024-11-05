/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Architectural state for the 'Smclic' fast interrupts extension. */

/* Smclic csrs */
mapping clause csr_name_map = 0x307  <-> "mtvt"
mapping clause csr_name_map = 0x345  <-> "mnxti"
mapping clause csr_name_map = 0xFB1  <-> "mintstatus"
mapping clause csr_name_map = 0x347  <-> "mintthresh"
mapping clause csr_name_map = 0x348  <-> "mscratchcsw"
mapping clause csr_name_map = 0x349  <-> "mscratchcswl"

function clause is_CSR_defined(0x307) = extensionEnabled(Ext_Smclic) // mtvt
function clause is_CSR_defined(0x345) = extensionEnabled(Ext_Smclic) // mnxti
function clause is_CSR_defined(0xFB1) = extensionEnabled(Ext_Smclic) // mintstatus
function clause is_CSR_defined(0x347) = extensionEnabled(Ext_Smclic) // mintthresh
function clause is_CSR_defined(0x348) = extensionEnabled(Ext_Smclic) & extensionEnabled(Ext_U) // mscratchcsw (not defined for M-only machines)
function clause is_CSR_defined(0x349) = extensionEnabled(Ext_Smclic) // mscratchcswl

/* Ssclic csrs */
mapping clause csr_name_map = 0x107  <-> "stvt"
mapping clause csr_name_map = 0x145  <-> "snxti"
mapping clause csr_name_map = 0xDB1  <-> "sintstatus"
mapping clause csr_name_map = 0x147  <-> "sintthresh"
mapping clause csr_name_map = 0x148  <-> "sscratchcsw"
mapping clause csr_name_map = 0x149  <-> "sscratchcswl"

function clause is_CSR_defined(0x107) = extensionEnabled(Ext_Ssclic) & extensionEnabled(Ext_S) // stvt
function clause is_CSR_defined(0x145) = extensionEnabled(Ext_Ssclic) & extensionEnabled(Ext_S) // snxti
function clause is_CSR_defined(0xDB1) = extensionEnabled(Ext_Ssclic) & extensionEnabled(Ext_S) // sintstatus
function clause is_CSR_defined(0x147) = extensionEnabled(Ext_Ssclic) & extensionEnabled(Ext_S) // sintthresh
function clause is_CSR_defined(0x148) = extensionEnabled(Ext_Ssclic) & extensionEnabled(Ext_S) // sscratchcsw
function clause is_CSR_defined(0x149) = extensionEnabled(Ext_Ssclic) & extensionEnabled(Ext_S) // sscratchcswl

// Internal state of accessing vector table, exception handler will decide which xinhv to set.
register inhv        : bits(1) = zeros()

register mtvt        : xlenbits = zeros()
register mintthresh  : ilbits = zeros()
register mil         : ilbits = zeros()

register stvt        : xlenbits = zeros()
register sintthresh  : ilbits = zeros()
register sil         : ilbits = zeros()

register clicintip   : bits(4096) = zeros()
register clicintie   : bits(4096) = zeros()
register clicintctl  : vector(4096, ilbits) = vector_init(zeros())
register clicintattr : vector(4096, Clicintattr) = vector_init(Mk_Clicintattr(zeros()))

// xintstatus is a read-only CSR that reads mil, sil and uil.
bitfield Mintstatus : xlenbits = {
  mil : 31 .. 24,
  sil : 15 .. 8,
}

// Get the read value of xintstatus. It is read-only.
function get_xintstatus(priv : Privilege) -> Mintstatus = {
  let r = Mk_Mintstatus(zeros());
  match priv {
    Machine => [r with mil=mil, sil=sil],
    Supervisor => [r with sil=sil],
    User => internal_error(__FILE__, __LINE__, "N extension not supported"),
  }
}

bitfield Cliccfg : bits(32) = {
  unlbits : 27 .. 24,
  snlbits : 19 .. 16,
  nmbits  : 5 .. 4,
  mnlbits : 3 .. 0,
}

register mcliccfg: Cliccfg = Mk_Cliccfg(zeros())

// val sys_xtvt_writable_bits = {c: "sys_xtvt_writable_bits", ocaml: "Platform.xtvt_writable_bits", _: "sys_xtvt_writable_bits"} : unit -> bits(64)
// TODO
function sys_xtvt_writable_bits() -> bits(64) = ones()

function legalize_tvt(o : xlenbits, v : xlenbits) -> xlenbits = {
  let mask = sys_xtvt_writable_bits()[xlen - 1 .. 0];
  let v = (v & mask) | (o & ~(mask));
  // "Values other than 0 in the low 6 bits of xtvt are reserved."
  // Here we'll just hard-wire them to 0.
  [v with 5..0 = zeros()]
}
