/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* The emulator fetch-execute-interrupt dispatch loop. */

/* returns whether to increment the step count in the trace */
function step(step_no : int) -> bool = {
  /* for step extensions */
  ext_pre_step_hook();

  /*
   * This records whether or not minstret should be incremented when
   * the instruction is retired. Since retirement occurs before CSR
   * writes we initialise it based on mcountinhibit here, before
   * mcountinhibit is potentially changed. We also mark minstret(h) as not
   * having been explicitly written yet.
   */
  minstret_increment = get_countinhibit()[IR] == 0b0;
  minstret_write = None();
  minstreth_write = None();

  clear_trigger_hits();
  tdata1_write = false;

  updateDebugPendingNMI();

  let (retired, stepped) : (Retired, bool) =
    match dispatchDebugEntry() {
      Some(retired, stepped) => (retired, stepped),
      None() => {
        if (dcsr.STEP()==0b1 & not(debug_mode_active)) then {
          pending_debug_entry_by_step = true;
        };
        if nmi_taken then {
          if   get_config_print_instr()
          then print_instr("Handling Non-Maskable Interrupt");
          handle_nmi();
          (RETIRE_FAIL, false)
        } else {
          match dispatchInterrupt(cur_privilege()) {
            Some(excode, priv) => {
              if   get_config_print_instr()
              then print_bits("Handling interrupt: ", excode);
              handle_interrupt(excode, priv);
              (RETIRE_FAIL, false)
            },
            None() => {
              check_for_external_sdtrig();
              match check_and_handle_pc_for_triggers(PC) {
                Some(ret) => (ret, false),
                None() => {
                  /* the extension hook interposes on the fetch result */
                  match ext_fetch_hook(fetch()) {
                    /* extension error */
                    F_Ext_Error(e)   => {
                      ext_handle_fetch_check_error(e);
                      (RETIRE_FAIL, false)
                    },
                    /* standard error */
                    F_Error(e, addr) => {
                      handle_mem_exception(addr, e);
                      (RETIRE_FAIL, false)
                    },
                    /* non-error cases: */
                    F_RVC(h) => {
                      sail_instr_announce(h);
                      instbits = zero_extend(h);
                      let ast = ext_decode_compressed(h);
                      if   get_config_print_instr()
                      then ext_print_instr(step_no, ast, h);
                      /* check for RVC once here instead of every RVC execute clause. */
                      if extensionEnabled(Ext_Zca) then {
                        nextPC = PC + 2;
                        match execute_instruction(ast) {
                          RETIRE_DEBUG_TRIGGER => (RETIRE_FAIL, false),
                          ret                  => (ret, true)
                        }
                      } else {
                        handle_illegal();
                        (RETIRE_FAIL, true)
                      }
                    },
                    F_Base(w) => {
                      sail_instr_announce(w);
                      instbits = zero_extend(w);
                      let ast = ext_decode(w);
                      ext_print_instr(step_no, ast, w);
                      nextPC = PC + 4;
                      match execute_instruction(ast) {
                          RETIRE_DEBUG_TRIGGER => (RETIRE_FAIL, false),
                          ret                  => (ret, true)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    };


  tick_pc();

  // Only increment minstret if the instruction retired successfully.
  if retired != RETIRE_SUCCESS then minstret_increment = false;

  update_minstret();

  update_hit_bits();

  /* for step extensions */
  ext_post_step_hook();

  stepped
}

// reset the chip
function reset() -> unit = {
  reset_sys();
  reset_vmem();

  ext_reset_misa();
  ext_reset();
}

/* initialize model state */
function init_model() -> unit = {
  // One-time initialisation.
  init_platform();
  // Reset CPU.
  reset();
}
