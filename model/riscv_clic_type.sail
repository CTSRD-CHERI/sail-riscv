/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Definitions for fast interrupt (Smclic extensions) */

// Interrupt level bits.
type ilbits = bits(8)

enum ClicTrigger = {
  ActiveHigh,
  PosEdge,
  ActiveLow,
  NegEdge,
}

mapping clic_trigger_bits : ClicTrigger <-> bits(2) = {
  ActiveHigh <-> 0b00,
  PosEdge    <-> 0b01,
  ActiveLow  <-> 0b10,
  NegEdge    <-> 0b11,
}

bitfield Clicintattr : bits(8) = {
  MODE : 7 .. 6,  // privilege mode
  TRIG : 2 .. 1,  // see ClicTrigger
  SHV  : 0,       // hardware vectored interrupt
}

union VectorTableFetchResult = {
  // Entry in vector table.
  F_TableEntry : xlenbits,
  // Standard exception and table entry addr.
  F_TableError : (ExceptionType, xlenbits),
}
