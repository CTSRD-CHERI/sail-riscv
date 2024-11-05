/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* default exception model */

type ext_exception = unit

/* Is XRET from given mode permitted by extension? */
function ext_check_xret_priv (p : Privilege) : Privilege -> bool = true
/* Called if above check fails */
function ext_fail_xret_priv () : unit -> unit = ()

function handle_trap_extension(p : Privilege, pc : xlenbits, u : option(unit)) -> unit = ()
function handle_nmi_extension(pc : xlenbits, handler_pc : xlenbits) -> unit = ()

/* used for traps and ECALL */
function prepare_trap_vector(p : Privilege, cause : Mcause) -> xlenbits = {
  let tvec : Mtvec = match p {
                       Machine    => Mk_Mtvec(get_mtvec()),
                       Supervisor => Mk_Mtvec(get_stvec()),
                       User       => internal_error(__FILE__, __LINE__, "Invalid privilege level"),
                     };
  match tvec_addr(tvec, cause) {
    Some(epc) => epc,
    None()    => internal_error(__FILE__, __LINE__, "Invalid tvec mode")
  }
}

val prepare_clic_xret_vectored_target : (Privilege) -> xlenbits

function prepare_xret_target(p : Privilege) -> xlenbits =
  if inSmclicMode() & get_xcause(p)[Xinhv] == 0b1
  then prepare_clic_xret_vectored_target(p)
  else get_xepc(p)
