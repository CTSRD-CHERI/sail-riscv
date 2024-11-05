/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

function vector_table_fetch(vaddr : xlenbits) -> VectorTableFetchResult =
  match translateAddr(vaddr, Read(Data)) {
    TR_Failure(e) => F_TableError(e, vaddr),
    TR_Address(paddr, pbmt, _) =>
      match mem_read(Execute(), pbmt, paddr, xlen_bytes, false, false, false) {
        MemException(e)       => F_TableError(e, vaddr),
        MemValue(table_entry) => F_TableEntry(table_entry),
      },
  }
