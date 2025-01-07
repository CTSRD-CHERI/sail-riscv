/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Physical memory model.
 *
 * This assumes that the platform memory map has been defined, so that accesses
 * to MMIO regions can be dispatched.
 *
 * The implementation below supports the reading and writing of memory
 * metadata in addition to raw memory data.
 *
 * The external API for this module is composed of three central functions
 *
 *   mem_read_priv_meta
 *   mem_write_ea
 *   mem_write_value_priv_meta
 *
 * and some special cases which partially apply these functions:
 *
 *   mem_read_priv - strips metadata from reads
 *   mem_read_meta - uses effectivePrivilege
 *   mem_read      - both of the above partial applications
 *
 *   mem_write_value_meta - uses effectivePrivilege
 *   mem_write_value_priv - uses a default value for metadata
 *   mem_write_value      - both of the above partial applications
 *
 * The internal implementation first performs a PMP check (if PMP is
 * enabled), and then dispatches to MMIO regions or physical memory as
 * per the platform memory map.
 */

function is_aligned_addr forall 'n. (addr : xlenbits, width : int('n)) -> bool =
  unsigned(addr) % width == 0

function read_kind_of_flags (aq : bool, rl : bool, res : bool) -> option(read_kind) =
  match (aq, rl, res) {
    (false, false, false) => Some(Read_plain),
    (true, false, false)  => Some(Read_RISCV_acquire),
    (true, true, false)   => Some(Read_RISCV_strong_acquire),
    (false, false, true)  => Some(Read_RISCV_reserved),
    (true, false, true)   => Some(Read_RISCV_reserved_acquire),
    (true, true, true)    => Some(Read_RISCV_reserved_strong_acquire),
    (false, true, false)  => None(), /* should these be instead throwing error_not_implemented as below? */
    (false, true, true)   => None()
  }

function write_kind_of_flags (aq : bool, rl : bool, con : bool) -> write_kind =
  match (aq, rl, con) {
    (false, false, false) => Write_plain,
    (false, true,  false) => Write_RISCV_release,
    (false, false, true)  => Write_RISCV_conditional,
    (false, true , true)  => Write_RISCV_conditional_release,
    (true,  true,  false) => Write_RISCV_strong_release,
    (true,  true , true)  => Write_RISCV_conditional_strong_release,
    // throw an illegal instruction here?
    (true,  false, false) => throw(Error_not_implemented("store.aq")),
    (true,  false, true)  => throw(Error_not_implemented("sc.aq"))
  }

// only used for actual memory regions, to avoid MMIO effects
function phys_mem_read forall 'n, 0 < 'n <= max_mem_access . (t : AccessType(ext_access_type), paddr : xlenbits, width : int('n), aq : bool, rl: bool, res : bool, meta : bool) -> MemoryOpResult((bits(8 * 'n), mem_meta)) = {
  let res = (match read_kind_of_flags(aq, rl, res) {
    Some(rk) => Some(read_ram(rk, paddr, width, meta)),
    None()   => None()
  }) : option((bits(8 * 'n), mem_meta));
  let res : option((bits(8 * 'n), mem_meta)) = if platform_get_rvfi_dii() & out_of_rvfi_dii_range(paddr, width) then None() else res;
  match (t, res) {
    (Execute(),  None()) => MemException(E_Fetch_Access_Fault()),
    (Read(Data), None()) => MemException(E_Load_Access_Fault()),
    (_,          None()) => MemException(E_SAMO_Access_Fault()),
    (_,      Some(v, m)) => { if   get_config_print_mem()
                              then print_mem("mem[" ^ to_str(t) ^ "," ^ BitStr(paddr) ^ "] -> " ^ BitStr(v));
                              MemValue(v, m) }
  }
}

type amo_level = range(0, 3)

val pma_amo_support_to_level : AtomicSupport -> amo_level
function pma_amo_support_to_level(a) = {
  match a {
    AMONone => 0,
    AMOSwap => 1,
    AMOLogical => 2,
    AMOArithmetic => 3,
  }
}

val amo_op_to_pma : amoop -> AtomicSupport
function amo_op_to_pma(op) = {
  match op {
    AMOSWAP => AMOSwap,
    AMOXOR => AMOLogical,
    AMOAND => AMOLogical,
    AMOOR => AMOLogical,
    AMOADD => AMOArithmetic,
    AMOMIN => AMOArithmetic,
    AMOMAX => AMOArithmetic,
    AMOMINU => AMOArithmetic,
    AMOMAXU => AMOArithmetic,
  }
}

function pmaCheck forall 'n, 0 < 'n <= max_mem_access .
(
  pbmt       : PBMT,
  paddr      : xlenbits,
  width      : int('n),
  accTy      : AccessType(ext_access_type),
  res_or_con : bool,
)  -> option(ExceptionType) = {
  match matching_pma(pma_regions, paddr, width) {
    None() => {
      Some(accessFaultFromAccessType(accTy))
    },
    Some(struct { attributes, _ }) => {
      let attributes = resolve_pma_pbmt(attributes, pbmt);
      let misaligned = not(is_aligned_addr(paddr, width));
      // Check if we need to raise an exception for misalignment.
      if misaligned & attributes.misalignmentCausesAccessFault then {
        Some(accessFaultFromAccessType(accTy))
      } else if misaligned & attributes.misalignmentCausesAlignmentFault then {
        Some(alignmentFaultFromAccessType(accTy))
      } else {
        // Check read/write/execute permissions.
        let canAccess : bool = match accTy {
          Execute() => attributes.executable,
          Read(_)   => attributes.readable & not(res_or_con & attributes.reservability == RsrvNone),
          Write(_)  => attributes.writable & not(res_or_con & attributes.reservability == RsrvNone),
          ReadWrite(_, _)  => attributes.readable &
                              attributes.writable &
                              // TODO: Extend ReadWrite with the specific
                              // type of AMO operation. For now we assume
                              // everything is arithmetic which is wrong.
                              (pma_amo_support_to_level(AMOArithmetic) <=
                                pma_amo_support_to_level(attributes.atomicSupport))
        };
        if canAccess then None() else Some(accessFaultFromAccessType(accTy))
      }
    }
  }
}

function alignmentOrAccessFaultPriority(exc : ExceptionType) -> range(0, 1) = {
  match exc {
    E_Fetch_Access_Fault() => 1,
    E_Load_Access_Fault()  => 1,
    E_SAMO_Access_Fault()  => 1,
    E_Fetch_Addr_Align()   => 0,
    E_Load_Addr_Align()    => 0,
    E_SAMO_Addr_Align()    => 0,
    e => internal_error(__FILE__, __LINE__, "Invalid exception: " ^ exceptionType_to_str(e))
  }
}

val highestPriorityAlignmentOrAccessFault : (ExceptionType, ExceptionType) -> ExceptionType
function highestPriorityAlignmentOrAccessFault  (l : ExceptionType, r : ExceptionType) -> ExceptionType = {
  if alignmentOrAccessFaultPriority(l) > alignmentOrAccessFaultPriority(r) then l else r
}

// Check if access is permitted according to PMPs and PMAs.
function phys_access_check forall 'n, 0 < 'n <= max_mem_access . (
  typ : AccessType(ext_access_type),
  priv : Privilege,
  pbmt : PBMT,
  paddr : xlenbits,
  width : int('n),
  res_or_con : bool,
) -> option(ExceptionType) = {
  let skip_pmp_check_debug = debug_mode_active;
  let pmpError : option(ExceptionType) = if sys_pmp_count() == 0 | ignore_mprv_in_debug() | skip_pmp_check_debug then None() else pmpCheck(paddr, width, typ, priv);
  let pmaError : option(ExceptionType) = pmaCheck(pbmt, paddr, width, typ, res_or_con);
  match (pmpError, pmaError) {
    (None(), None())     => None(),
    (Some(e), None())    => Some(e),
    (None(), Some(e))    => Some(e),
    (Some(e0), Some(e1)) => Some(highestPriorityAlignmentOrAccessFault(e0, e1)),
  }
}

$ifdef RVFI_DII
val rvfi_read : forall 'n, 'n > 0. (xlenbits, int('n), MemoryOpResult((bits(8 * 'n), mem_meta))) -> unit
function rvfi_read (addr, width, result) = {
  rvfi_mem_data[rvfi_mem_addr] = zero_extend(addr);
  rvfi_mem_data_present = true;
  match result {
    /* TODO: report tag bit for capability writes and extend mask by one bit. */
    MemValue(v, _) => if width <= 16
                       then { rvfi_mem_data[rvfi_mem_rdata] = sail_zero_extend(v, 256);
                              rvfi_mem_data[rvfi_mem_rmask] = rvfi_encode_width_mask(width) }
                       else { internal_error(__FILE__, __LINE__, "Expected at most 16 bytes here!") },
    MemException(_) => ()
  };
}
$else
val rvfi_read : forall 'n, 'n > 0. (xlenbits, int('n), MemoryOpResult((bits(8 * 'n), mem_meta))) -> unit
function rvfi_read (addr, width, result) = ()
$endif

/* dispatches to MMIO regions or physical memory regions depending on physical memory map */
function checked_mem_read forall 'n, 0 < 'n <= max_mem_access . (
  typ : AccessType(ext_access_type),
  priv : Privilege,
  pbmt : PBMT,
  paddr : xlenbits,
  width : int('n),
  aq : bool,
  rl : bool,
  res: bool,
  meta : bool,
) -> MemoryOpResult((bits(8 * 'n), mem_meta)) = {
  let result : MemoryOpResult((bits(8 * 'n), mem_meta)) =
    if (aq | res) & not(is_aligned_addr(paddr, width))
    then MemException(E_Load_Addr_Align())
    else match (aq, rl, res) {
      (false, true,  false) => throw(Error_not_implemented("load.rl")),
      (false, true,  true)  => throw(Error_not_implemented("lr.rl")),
      _ => match phys_access_check(typ, priv, pbmt, paddr, width, res) {
        Some(e) => MemException(e),
        None() => {
          if  within_mmio_readable(paddr, width)
          then MemoryOpResult_add_meta(mmio_read(typ, paddr, width), default_meta)
          else match ext_check_phys_mem_read(typ, paddr, width, aq, rl, res, meta) {
            Ext_PhysAddr_OK()     => phys_mem_read(typ, paddr, width, aq, rl, res, meta),
            Ext_PhysAddr_Error(e) => MemException(e)
          }
        }
      },
    };
  rvfi_read(paddr, width, result);
  result
}



/* Atomic accesses can be done to MMIO regions, e.g. in kernel access to device registers. */

val mem_read           : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), PBMT, xlenbits, int('n), bool, bool, bool)                  -> MemoryOpResult(bits(8 * 'n))
val mem_read_priv      : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), Privilege, PBMT, xlenbits, int('n), bool, bool, bool)       -> MemoryOpResult(bits(8 * 'n))
val mem_read_meta      : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), PBMT, xlenbits, int('n), bool, bool, bool, bool)            -> MemoryOpResult((bits(8 * 'n), mem_meta))
val mem_read_priv_meta : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), Privilege, PBMT, xlenbits, int('n), bool, bool, bool, bool) -> MemoryOpResult((bits(8 * 'n), mem_meta))

/* The most generic memory read operation */
function mem_read_priv_meta (typ, priv, pbmt, paddr, width, aq, rl, res, meta) =
  checked_mem_read(typ, priv, pbmt, paddr, width, aq, rl, res, meta)

function mem_read_meta (typ, pbmt, paddr, width, aq, rl, res, meta) =
  mem_read_priv_meta(typ, effectivePrivilege(typ, mstatus, cur_privilege()), pbmt, paddr, width, aq, rl, res, meta)

/* Specialized mem_read_meta that drops the metadata */
function mem_read_priv (typ, priv, pbmt, paddr, width, aq, rl, res) =
  MemoryOpResult_drop_meta(mem_read_priv_meta(typ, priv, pbmt, paddr, width, aq, rl, res, false))

/* Specialized mem_read_priv that operates at the default effective privilege */
function mem_read (typ, pbmt, paddr, width, aq, rel, res) =
  mem_read_priv(typ, effectivePrivilege(typ, mstatus, cur_privilege()), pbmt, paddr, width, aq, rel, res)

val mem_write_ea : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bool, bool, bool) -> MemoryOpResult(unit)
function mem_write_ea (addr, width, aq, rl, con) =
  if (rl | con) & not(is_aligned_addr(addr, width))
  then MemException(E_SAMO_Addr_Align())
  else MemValue(write_ram_ea(write_kind_of_flags(aq, rl, con), addr, width))

$ifdef RVFI_DII
val rvfi_write : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), mem_meta, MemoryOpResult(bool)) -> unit
function rvfi_write (addr, width, value, meta, result) = {
  rvfi_mem_data[rvfi_mem_addr] = zero_extend(addr);
  rvfi_mem_data_present = true;
  match result {
    /* Log only the memory address (without the value) if the write fails. */
    MemValue(_) => if width <= 16 then {
        /* TODO: report tag bit for capability writes and extend mask by one bit. */
        rvfi_mem_data[rvfi_mem_wdata] = sail_zero_extend(value,256);
        rvfi_mem_data[rvfi_mem_wmask] = rvfi_encode_width_mask(width);
      } else {
        internal_error(__FILE__, __LINE__, "Expected at most 16 bytes here!");
      },
    MemException(_) => ()
  }
}
$else
val rvfi_write : forall 'n, 'n > 0. (xlenbits, int('n), bits(8 * 'n), mem_meta, MemoryOpResult(bool)) -> unit
function rvfi_write (addr, width, value, meta, result) = ()
$endif

// only used for actual memory regions, to avoid MMIO effects
function phys_mem_write forall 'n, 0 < 'n <= max_mem_access . (wk : write_kind, paddr : xlenbits, width : int('n), data : bits(8 * 'n), meta : mem_meta) -> MemoryOpResult(bool) = {
  if platform_get_rvfi_dii() & out_of_rvfi_dii_range(paddr, width)
  then MemException(E_SAMO_Access_Fault())
  else {
    let res = MemValue(write_ram(wk, paddr, width, data, meta));
    if   get_config_print_mem()
    then print_mem("mem[" ^ BitStr(paddr) ^ "] <- " ^ BitStr(data));
    res
  }
}

/* dispatches to MMIO regions or physical memory regions depending on physical memory map */
function checked_mem_write forall 'n, 0 < 'n <= max_mem_access . (
  pbmt : PBMT,
  paddr : xlenbits,
  width : int('n),
  data : bits(8 * 'n),
  typ : AccessType(ext_access_type),
  priv : Privilege,
  aq : bool,
  rl : bool,
  con : bool,
  meta : mem_meta,
) -> MemoryOpResult(bool) = {
  let result : MemoryOpResult(bool) =
    if (rl | con) & not(is_aligned_addr(paddr, width))
    then MemException(E_SAMO_Addr_Align())
    else match phys_access_check(typ, priv, pbmt, paddr, width, con) {
      Some(e) => MemException(e),
      None() => {
        if within_mmio_writable(paddr, width)
        then mmio_write(paddr, width, data)
        else {
          let wk = write_kind_of_flags(aq, rl, con);
          match ext_check_phys_mem_write (wk, paddr, width, data, meta) {
            Ext_PhysAddr_OK()      => phys_mem_write(wk, paddr, width, data, meta),
            Ext_PhysAddr_Error(e)  => MemException(e)
          }
        }
      }
    };
  rvfi_write(paddr, width, data, meta, result);
  result
}

/* Atomic accesses can be done to MMIO regions, e.g. in kernel access to device registers. */

/* Memory write with an explicit metadata value.  Metadata writes are
 * currently assumed to have the same alignment constraints as their
 * data.
 * NOTE: The wreg effect is due to MMIO, the rreg is due to checking mtime.
 */
val mem_write_value_priv_meta : forall 'n, 0 < 'n <= max_mem_access . (PBMT, xlenbits, int('n), bits(8 * 'n), AccessType(ext_access_type), Privilege, mem_meta, bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_priv_meta (pbmt, paddr, width, value, typ, priv, meta, aq, rl, con) =
  checked_mem_write(pbmt, paddr, width, value, typ, priv, aq, rl, con, meta)

/* Memory write with explicit Privilege, implicit AccessType and metadata */
val mem_write_value_priv : forall 'n, 0 < 'n <= max_mem_access . (PBMT, xlenbits, int('n), bits(8 * 'n), Privilege, bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_priv (pbmt, paddr, width, value, priv, aq, rl, con) =
  mem_write_value_priv_meta(pbmt, paddr, width, value, Write(default_write_acc), priv, default_meta, aq, rl, con)

/* Memory write with explicit metadata and AccessType, implicit and Privilege */
val mem_write_value_meta : forall 'n, 0 < 'n <= max_mem_access . (PBMT, xlenbits, int('n), bits(8 * 'n), ext_access_type, mem_meta, bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_meta (pbmt, paddr, width, value, ext_acc, meta, aq, rl, con) = {
  let typ = Write(ext_acc);
  let ep = effectivePrivilege(typ, mstatus, cur_privilege());
  mem_write_value_priv_meta(pbmt, paddr, width, value, typ, ep, meta, aq, rl, con)
}

/* Memory write with default AccessType, Privilege, and metadata */
val mem_write_value : forall 'n, 0 < 'n <= max_mem_access . (PBMT, xlenbits, int('n), bits(8 * 'n), bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value (pbmt, paddr, width, value, aq, rl, con) = {
  mem_write_value_meta(pbmt, paddr, width, value, default_write_acc, default_meta, aq, rl, con)
}

/* Same as mem_write_value but uses ReadWrite for the access type instead of Write. */
val mem_write_value_amo : forall 'n, 0 < 'n <= max_mem_access . (PBMT, xlenbits, int('n), bits(8 * 'n), bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_amo (pbmt, paddr, width, value, aq, rl, con) = {
  let typ = ReadWrite(default_write_acc, default_write_acc);
  let ep = effectivePrivilege(typ, mstatus, cur_privilege());
  mem_write_value_priv_meta(pbmt, paddr, width, value, typ, ep, default_meta, aq, rl, con)
}
