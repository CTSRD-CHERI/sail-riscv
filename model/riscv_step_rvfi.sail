/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Step hooks for rvfi. */

function ext_fetch_hook(f : FetchResult) -> FetchResult = f

function ext_pre_step_hook()  -> unit = ()

function ext_post_step_hook() -> unit = {
  /* record the next pc */
  rvfi_pc_data[rvfi_pc_wdata] = zero_extend(get_arch_pc())
}

val reset_base_regs : unit -> unit
function reset_base_regs () = {
  x1  = zero_reg;
  x2  = zero_reg;
  x3  = zero_reg;
  x4  = zero_reg;
  x5  = zero_reg;
  x6  = zero_reg;
  x7  = zero_reg;
  x8  = zero_reg;
  x9  = zero_reg;
  x10 = zero_reg;
  x11 = zero_reg;
  x12 = zero_reg;
  x13 = zero_reg;
  x14 = zero_reg;
  x15 = zero_reg;
  x16 = zero_reg;
  x17 = zero_reg;
  x18 = zero_reg;
  x19 = zero_reg;
  x20 = zero_reg;
  x21 = zero_reg;
  x22 = zero_reg;
  x23 = zero_reg;
  x24 = zero_reg;
  x25 = zero_reg;
  x26 = zero_reg;
  x27 = zero_reg;
  x28 = zero_reg;
  x29 = zero_reg;
  x30 = zero_reg;
  x31 = zero_reg
}

val reset_fdext_regs : unit -> unit
function reset_fdext_regs () = {
  f0  = zero_freg;
  f1  = zero_freg;
  f2  = zero_freg;
  f3  = zero_freg;
  f4  = zero_freg;
  f5  = zero_freg;
  f6  = zero_freg;
  f7  = zero_freg;
  f8  = zero_freg;
  f9  = zero_freg;
  f10 = zero_freg;
  f11 = zero_freg;
  f12 = zero_freg;
  f13 = zero_freg;
  f14 = zero_freg;
  f15 = zero_freg;
  f16 = zero_freg;
  f17 = zero_freg;
  f18 = zero_freg;
  f19 = zero_freg;
  f20 = zero_freg;
  f21 = zero_freg;
  f22 = zero_freg;
  f23 = zero_freg;
  f24 = zero_freg;
  f25 = zero_freg;
  f26 = zero_freg;
  f27 = zero_freg;
  f28 = zero_freg;
  f29 = zero_freg;
  f30 = zero_freg;
  f31 = zero_freg
}

val ext_reset : unit -> unit
function ext_reset() = {
  reset_base_regs();
  reset_fdext_regs();
  /* these are here so that the C backend doesn't prune them out. */
  // let _ = rvfi_step(0);
  ext_rvfi_reset();
  ext_cheri_reset();
  ()
}

function ext_reset_misa() -> unit = ext_cheri_reset_misa()
