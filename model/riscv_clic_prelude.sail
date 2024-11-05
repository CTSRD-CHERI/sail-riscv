/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

// CLIC extensions - put here to include in prelude as used in riscv_types.sail

val sys_enable_smclic = {c: "sys_enable_smclic", ocaml: "Platform.enable_smclic", _: "sys_enable_smclic"} : unit -> bool
val sys_enable_smclicconfig = {c: "sys_enable_smclicconfig", ocaml: "Platform.enable_smclicconfig", _: "sys_enable_smclicconfig"} : unit -> bool
val sys_enable_smclicshv = {c: "sys_enable_smclicshv", ocaml: "Platform.enable_smclicshv", _: "sys_enable_smclicshv"} : unit -> bool
val sys_enable_ssclic = {c: "sys_enable_ssclic", ocaml: "Platform.enable_ssclic", _: "sys_enable_ssclic"} : unit -> bool

enum clause extension = Ext_Smclic
function clause extensionEnabled(Ext_Smclic) = sys_enable_smclic()

enum clause extension = Ext_Smclicconfig
function clause extensionEnabled(Ext_Smclicconfig) = sys_enable_smclicconfig()

// Selective Hardware Vectoring
enum clause extension = Ext_Smclicshv
function clause extensionEnabled(Ext_Smclicshv) = sys_enable_smclicshv()

enum clause extension = Ext_Ssclic
function clause extensionEnabled(Ext_Ssclic) = sys_enable_smclic() & sys_enable_ssclic()

enum clause extension = Ext_Suclic
function clause extensionEnabled(Ext_Suclic) = false
