/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

union clause ast = DRET : unit

mapping clause encdec = DRET()
  <-> 0b0111101 @ 0b10010 @ 0b00000 @ 0b000 @ 0b00000 @ 0b1110011

function clause execute DRET() = {
  if debug_mode_active then {
    leave_debug_mode();
    RETIRE_SUCCESS
  } else {
    handle_illegal();
    RETIRE_FAIL
  }
}

mapping clause assembly = DRET() <-> "dret"
