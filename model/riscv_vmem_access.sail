// Exponent of the page size. 2^12 = 4096 bytes.
type page_size_exp : Int = 12
let  page_size_exp = sizeof(page_size_exp)
type page_size : Int = 2 ^ page_size_exp
let  page_size = sizeof(page_size)

type translation = (xlenbits, PBMT, ext_ptw)

// Exception when accessing an address, together with the offending virtual address.
type VMemException = (xlenbits, ExceptionType)

// An address, plus an optional second address. This is used for address
// translation of accesses that may span page boundaries. It's not possible
// to span more than one page boundary so we only need a max of two addresses.
type translation2 = (translation, option(translation))

// For an access that may be split across a page boundary, returns the width
// of each half. If it isn't split the second value will be 0.
val splitAccessWidths : forall 'w, 0 <= 'w <= max_mem_access . (xlenbits, int('w)) ->
  {'w0 'w1, 'w0 >= 0 & 'w1 >= 0 & 'w0 + 'w1 == 'w . (int('w0), int('w1))}

function splitAccessWidths(addr, width) = {
  let offset_in_page = unsigned(addr[page_size_exp - 1 .. 0]);
  let width0 = page_size - offset_in_page;
  let width0 : range(0, 'w) = if width0 <= width then width0 else width;
  let width1 = width - width0;
  (width0, width1)
}

// Translate virtual to physical address(es) for a multi-byte memory access.
// Because the access may be across a page boundary this may result in multiple
// physical addresses. If that is the case, the second physical address will
// point to the start of a page.
function translateRange(
  vaddr : xlenbits,
  width : range(0, max_mem_access),
  typ : AccessType(ext_access_type),
) -> result(translation2, VMemException) = {
  // Widths of each access.
  let (width0, width1) = splitAccessWidths(vaddr, width);
  assert(width0 + width1 == width);

  // Translate the first address, return failure if it fails.
  let tr0 : translation = match translateAddr(vaddr, typ) {
    TR_Address(a) => a,
    TR_Failure(exc) => return Err(vaddr, exc),
  };

  // If the second access exists then we need to translate its address.
  let tr1 = if width1 != 0 then {
    // Second address to translate is at the start of the next page (wrapped).
    let vaddr1 = vaddr + width0;
    let tr1 : translation = match translateAddr(vaddr1, typ) {
      TR_Address(paddr, pbmt, ext) => (paddr, pbmt, ext),
      TR_Failure(exc) => return Err(vaddr1, exc),
    };
    Some(tr1)
  } else {
    None()
  };
  Ok(tr0, tr1)
}

// Read memory but potentially using two accesses if `paddrs` contains two
// entries. The results are then combined back into a single value. This is
// needed when reading across a page boundary.
function vmem_read_priv_meta forall 'n, 0 < 'n < max_mem_access . (
  typ : AccessType(ext_access_type),
  priv : Privilege,
  vaddr : xlenbits,
  width : int('n),
  aq : bool,
  rel : bool,
  res : bool,
  meta : bool,
) -> result((bits(8 * 'n), mem_meta), VMemException) = {
  match translateRange(vaddr, width, typ) {
    Err(e) => Err(e),
    Ok(tr) => {
      match tr {
        ((paddr0, pbmt0, _), None()) => match checked_mem_read(typ, priv, pbmt0, paddr0, width, aq, rel, res, meta) {
          MemValue(v, meta) => Ok(v, meta),
          MemException(e) => Err(vaddr, e),
        },
        ((paddr0, pbmt0, _), Some((paddr1, pbmt1, _))) => {
          let (width0 as int('w0), width1 as int('w1)) = splitAccessWidths(paddr0, width);
          assert(width0 > 0 & width1 > 0);

          let (val0, meta0) : (bits(8 * 'w0), mem_meta) = match checked_mem_read(typ, priv, pbmt0, paddr0, width0, aq, rel, res, meta) {
            MemValue(v, meta) => (v, meta),
            MemException(e) => return Err(vaddr, e),
          };
          let (val1, meta1) : (bits(8 * 'w1), mem_meta) = match checked_mem_read(typ, priv, pbmt1, paddr1, width1, aq, rel, res, meta) {
            MemValue(v, meta) => (v, meta),
            MemException(e) => return Err(vaddr + width0, e),
          };
          // TODO: How should we combine meta0 and meta1?
          Ok((val1 @ val0, meta0))
        },
      }
    },
  };

}

struct _WriteIntermediateState('n) = {
  vaddr : xlenbits,
  tr : translation2,
  width : int('n),
  typ : AccessType(ext_access_type),
  aq : bool,
  rl : bool,
  con : bool,
}

function vmem_write_translate forall 'n, 0 < 'n <= max_mem_access . (
  vaddr : xlenbits,
  width : int('n),
  typ : AccessType(ext_access_type),
  aq : bool,
  rl : bool,
  con : bool,
) -> result(_WriteIntermediateState('n), VMemException) = {
  // Translate both addresses.
  match translateRange(vaddr, width, typ) {
    Err(e) => Err(e),
    Ok(tr) => {
      match tr {
        ((paddr0, _, _), None()) => match mem_write_ea(paddr0, width, aq, rl, con) {
          MemValue() => Ok(struct { vaddr, tr, width, typ, aq, rl, con }),
          MemException(e) => Err(vaddr, e),
        },
        ((paddr0, _, _), Some((paddr1, _, _))) => {
          let (width0, width1) = splitAccessWidths(paddr0, width);
          assert(width0 > 0 & width1 > 0);

          match mem_write_ea(paddr0, width0, aq, rl, con) {
            MemValue() => (),
            MemException(e) => return Err(vaddr, e),
          };
          match mem_write_ea(paddr1, width1, aq, rl, con) {
            MemValue() => (),
            MemException(e) => return Err(vaddr + width0, e),
          };
          Ok(struct { vaddr, tr, width, typ, aq, rl, con })
        },
      }
    },
  }
}

function vmem_write_value_priv_meta forall 'n, 0 < 'n <= max_mem_access . (
  state : _WriteIntermediateState('n),
  value : bits(8 * 'n),
  priv : Privilege,
  meta : mem_meta,
) -> result(bool, VMemException) = {
  let (vaddr, tr, width, typ, aq, rl, con) = (state.vaddr, state.tr, state.width, state.typ, state.aq, state.rl, state.con);

  match tr {
    ((paddr0, pbmt0, _), None()) => match checked_mem_write(pbmt0, paddr0, width, value, typ, priv, aq, rl, con, meta) {
      MemValue(ok) => Ok(ok),
      MemException(e) => Err(vaddr, e),
    },
    ((paddr0, pbmt0, _), Some((paddr1, pbmt1, _))) => {
      let (width0, width1) = splitAccessWidths(paddr0, width);
      assert(width0 > 0 & width1 > 0);

      let res0 : bool = match checked_mem_write(pbmt0, paddr0, width0, value[8 * width0 - 1 .. 0], typ, priv, aq, rl, con, meta) {
        MemValue(ok) => ok,
        MemException(e) => return Err(vaddr, e),
      };
      let res1 : bool = match checked_mem_write(pbmt1, paddr1, width1, value[8 * width - 1 .. 8 * width0], typ, priv, aq, rl, con, meta) {
        MemValue(ok) => ok,
        MemException(e) => return Err(vaddr, e),
      };
      // TODO: The semantics of this return value are unclear, and currently always true.
      Ok(res1 & res0)
    },
  }
}


// Convenience functions wrapping the above functions to match those in riscv_mem.sail.

// Don't read or return meta.
function vmem_read_priv forall 'n, 0 < 'n < max_mem_access . (
  typ : AccessType(ext_access_type),
  priv : Privilege,
  vaddr : xlenbits,
  width : int('n),
  aq : bool,
  rel : bool,
  res : bool,
) -> result(bits(8 * 'n), VMemException) =
  match vmem_read_priv_meta(typ, priv, vaddr, width, aq, rel, res, false) {
    Ok(v, _) => Ok(v),
    Err(vaddr, e) => Err(vaddr, e),
  }

// Use default privilege.
function vmem_read_meta forall 'n, 0 < 'n < max_mem_access . (
  typ : AccessType(ext_access_type),
  vaddr : xlenbits,
  width : int('n),
  aq : bool,
  rel : bool,
  res : bool,
  meta : bool,
) -> result((bits(8 * 'n), mem_meta), VMemException) =
  vmem_read_priv_meta(typ, effectivePrivilege(typ, mstatus, cur_privilege()), vaddr, width, aq, rel, res, meta)

// Don't read or return meta and use default privilege.
function vmem_read forall 'n, 0 < 'n < max_mem_access . (
  typ : AccessType(ext_access_type),
  vaddr : xlenbits,
  width : int('n),
  aq : bool,
  rel : bool,
  res : bool,
) -> result(bits(8 * 'n), VMemException) =
  vmem_read_priv(typ, effectivePrivilege(typ, mstatus, cur_privilege()), vaddr, width, aq, rel, res)

// Write default metadata.
function vmem_write_value_priv forall 'n, 0 < 'n <= max_mem_access . (
  state : _WriteIntermediateState('n),
  value : bits(8 * 'n),
  priv : Privilege,
) -> result(bool, VMemException) =
  vmem_write_value_priv_meta(state, value, priv, default_meta)

// Use default privilege.
function vmem_write_value_meta forall 'n, 0 < 'n <= max_mem_access . (
  state : _WriteIntermediateState('n),
  value : bits(8 * 'n),
  meta : mem_meta,
) -> result(bool, VMemException) =
  vmem_write_value_priv_meta(state, value, effectivePrivilege(state.typ, mstatus, cur_privilege()), meta)

// Write default metadata and use default privilege.
function vmem_write_value forall 'n, 0 < 'n <= max_mem_access . (
  state : _WriteIntermediateState('n),
  value : bits(8 * 'n),
) -> result(bool, VMemException) =
  vmem_write_value_meta(state, value, default_meta)
