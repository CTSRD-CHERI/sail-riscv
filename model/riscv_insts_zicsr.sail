/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* ****************************************************************** */
/* This file specifies the instructions in the 'Zicsr' extension.     */

/* ****************************************************************** */
union clause ast = CSR  : (csreg, regidx, regidx, bool, csrop)

mapping encdec_csrop : csrop <-> bits(2) = {
  CSRRW <-> 0b01,
  CSRRS <-> 0b10,
  CSRRC <-> 0b11
}

mapping clause encdec = CSR(csr, rs1, rd, is_imm, op)
  <-> csr @ rs1 @ bool_bits(is_imm) @ encdec_csrop(op) @ rd @ 0b1110011

// TODO: These read/write_CSR definitions should be moved to the files
// corresponding to their extensions rather than all be here.

/* machine mode */
function clause read_CSR(0xF11, _) = zero_extend(mvendorid)
function clause read_CSR(0xF12, _) = marchid
function clause read_CSR(0xF13, _) = mimpid
function clause read_CSR(0xF14, _) = mhartid
function clause read_CSR(0xF15, _) = mconfigptr
function clause read_CSR(0x300, _) = get_xstatus(Machine)
function clause read_CSR(0x301, _) = misa.bits
function clause read_CSR(0x302, _) = medeleg.bits
function clause read_CSR(0x303, _) = mideleg.bits
function clause read_CSR(0x304, _) = if inSmclicMode() then zeros() else mie.bits
function clause read_CSR(0x305, _) = get_mtvec()
function clause read_CSR(0x306, _) = zero_extend(mcounteren.bits)
function clause read_CSR(0x30A, _) = menvcfg.bits[xlen - 1 .. 0]
function clause read_CSR((0x310, _) if xlen == 32) = mstatush.bits
function clause read_CSR((0x31A, _) if xlen == 32) = menvcfg.bits[63 .. 32]
function clause read_CSR(0x747, _) = mseccfg.bits[xlen - 1 .. 0]
function clause read_CSR((0x757, _) if xlen == 32) = mseccfg.bits[63 .. 32]
function clause read_CSR(0x320, _) = zero_extend(get_countinhibit().bits)

/* Hardware Performance Monitoring event selection */
function clause read_CSR((0b0011001 /* 0x320 */ @ index : bits(5), _) if unsigned(index) >= 3) = read_mhpmevent(hpmidx_from_bits(index))

function clause read_CSR(0x340, _) = get_mscratch()
function clause read_CSR(0x341, _) = get_mepc()
function clause read_CSR(0x342, _) = get_xcause(Machine).bits
function clause read_CSR(0x343, _) = mtval
function clause read_CSR(0x344, _) = if inSmclicMode() then zeros() else mip.bits

// pmpcfgN
function clause read_CSR((0x3A @ idx : bits(4), _) if idx[0] == bitzero | xlen == 32) = pmpReadCfgReg(unsigned(idx))
// pmpaddrN. Unfortunately the PMP index does not nicely align with the CSR index bits.
function clause read_CSR(0x3B @ idx : bits(4), _) = pmpReadAddrReg(unsigned(0b00 @ idx))
function clause read_CSR(0x3C @ idx : bits(4), _) = pmpReadAddrReg(unsigned(0b01 @ idx))
function clause read_CSR(0x3D @ idx : bits(4), _) = pmpReadAddrReg(unsigned(0b10 @ idx))
function clause read_CSR(0x3E @ idx : bits(4), _) = pmpReadAddrReg(unsigned(0b11 @ idx))

/* machine mode counters */
function clause read_CSR(0xB00, _) = mcycle[(xlen - 1) .. 0]
function clause read_CSR(0xB02, _) = minstret[(xlen - 1) .. 0]
function clause read_CSR((0xB80, _) if xlen == 32)= mcycle[63 .. 32]
function clause read_CSR((0xB82, _) if xlen == 32) = minstret[63 .. 32]

/* Hardware Performance Monitoring machine mode counters */
function clause read_CSR((0b1011000 /* 0xB00 */ @ index : bits(5), _) if unsigned(index) >= 3) = read_mhpmcounter(hpmidx_from_bits(index))
function clause read_CSR((0b1011100 /* 0xB80 */ @ index : bits(5), _) if xlen == 32 & unsigned(index) >= 3) = read_mhpmcounterh(hpmidx_from_bits(index))

/* Sdtrig and Sdext registers */
function clause read_CSR(0x7a0, _) = tselect
function clause read_CSR(0x7a1, _) = {
  match unsigned(tselect){
    trig if 0 <= trig & trig < 6 => read_tdata1_underlying(trig),
    v => internal_error(__FILE__, __LINE__, "Currently unsupported tselect " ^ dec_str(v))
  }
}
function clause read_CSR(0x7a2, _) = {
  match unsigned(tselect){
    trig if 0 <= trig & trig < 6 => read_tdata2_underlying(trig),
    v => internal_error(__FILE__, __LINE__, "Currently unsupported tselect " ^ dec_str(v))
  }
}
function clause read_CSR(0x7a4, _) = { legalize_tinfo(zeros()).bits() }
function clause read_CSR(0x7a5, _) = tcontrol.bits()
function clause read_CSR(0x7b0, _) = zero_extend(dcsr.bits())
function clause read_CSR(0x7b1, _) = get_dpc()
function clause read_CSR(0x7b2, _) = get_dscratch0()
function clause read_CSR(0x7b3, _) = get_dscratch1()

/* supervisor mode */
function clause read_CSR(0x100, _) = get_xstatus(Supervisor)
function clause read_CSR(0x104, _) = if inSmclicMode() then zeros() else lower_mie(mie, mideleg).bits
function clause read_CSR(0x105, _) = get_stvec()
function clause read_CSR(0x106, _) = zero_extend(scounteren.bits)
function clause read_CSR(0x10A, _) = senvcfg.bits[xlen - 1 .. 0]
function clause read_CSR(0x140, _) = get_sscratch()
function clause read_CSR(0x141, _) = get_sepc()
function clause read_CSR(0x142, _) = get_xcause(Supervisor).bits
function clause read_CSR(0x143, _) = stval
function clause read_CSR(0x144, _) = if inSmclicMode() then zeros() else lower_mip(mip, mideleg).bits
function clause read_CSR(0x14D, _) = stimecmp[xlen - 1 .. 0]
function clause read_CSR((0x15D, _) if xlen == 32) = stimecmp[63 .. 32]
function clause read_CSR(0x180, _) = satp

/* user mode counters */
function clause read_CSR(0xC00, _) = mcycle[(xlen - 1) .. 0]
function clause read_CSR(0xC01, _) = mtime[(xlen - 1) .. 0]
function clause read_CSR(0xC02, _) = minstret[(xlen - 1) .. 0]
function clause read_CSR((0xC80, _) if xlen == 32) = mcycle[63 .. 32]
function clause read_CSR((0xC81, _) if xlen == 32) = mtime[63 .. 32]
function clause read_CSR((0xC82, _) if xlen == 32) = minstret[63 .. 32]

/* Hardware Performance Monitoring user mode counters */
function clause read_CSR((0b1100000 /* 0xC00 */ @ index : bits(5), _) if unsigned(index) >= 3) = read_mhpmcounter(hpmidx_from_bits(index))
function clause read_CSR((0b1100100 /* 0xC80 */ @ index : bits(5), _) if xlen == 32 & unsigned(index) >= 3) = read_mhpmcounterh(hpmidx_from_bits(index))

/* user mode: Zkr */
function clause read_CSR(0x015, _) = read_seed_csr()

/* machine mode */
function clause write_CSR(0x300, value) = { set_xstatus(Machine, value); mstatus.bits }
function clause write_CSR((0x310, value) if xlen == 32) = { mstatush.bits } // ignore writes for now
function clause write_CSR(0x301, value) = { misa = legalize_misa(misa, value); misa.bits }
function clause write_CSR(0x302, value) = { medeleg = legalize_medeleg(medeleg, value); medeleg.bits }
function clause write_CSR(0x303, value) = { mideleg = legalize_mideleg(mideleg, value); mideleg.bits }
function clause write_CSR(0x304, value) = { if inSmclicMode() then zeros() else { mie = legalize_mie(mie, value); mie.bits } }
function clause write_CSR(0x305, value) = { set_mtvec(value); get_mtvec() }
function clause write_CSR(0x306, value) = { mcounteren = legalize_mcounteren(mcounteren, value); zero_extend(mcounteren.bits) }
function clause write_CSR((0x30A, value) if xlen == 32) = { set_menvcfg(menvcfg.bits[63 .. 32] @ value); menvcfg.bits[31 .. 0] }
function clause write_CSR((0x30A, value) if xlen == 64) = { set_menvcfg(value); menvcfg.bits }
function clause write_CSR((0x31A, value) if xlen == 32) = { set_menvcfg(value @ menvcfg.bits[31 .. 0]); menvcfg.bits[63 .. 32] }
function clause write_CSR((0x747, value) if xlen == 32) = { set_mseccfg(mseccfg.bits[63 .. 32] @ value); mseccfg.bits[31 .. 0] }
function clause write_CSR((0x747, value) if xlen == 64) = { set_mseccfg(value); mseccfg.bits }
function clause write_CSR((0x757, value) if xlen == 32) = { set_mseccfg(value @ mseccfg.bits[31 .. 0]); mseccfg.bits[63 .. 32] }
function clause write_CSR(0x320, value) = { mcountinhibit = legalize_mcountinhibit(mcountinhibit, value); zero_extend(get_countinhibit().bits) }
function clause write_CSR(0x340, value) = { set_mscratch(value); get_mscratch() }
function clause write_CSR(0x341, value) = { set_mepc(value); get_mepc() }
function clause write_CSR(0x342, value) = { set_xcause(Machine, value); get_xcause(Machine).bits }
function clause write_CSR(0x343, value) = { mtval = convertInvalidAddr(value); mtval }
function clause write_CSR(0x344, value) = { if inSmclicMode() then zeros() else { mip = legalize_mip(mip, value); mip.bits } }

// pmpcfgN
function clause write_CSR((0x3A @ idx : bits(4), value) if idx[0] == bitzero | xlen == 32) = {
  let idx = unsigned(idx);
  pmpWriteCfgReg(idx, value);
  pmpReadCfgReg(idx)
}

// pmpaddrN. Unfortunately the PMP index does not nicely align with the CSR index bits.
function clause write_CSR(0x3B @ idx : bits(4), value) = { let idx = unsigned(0b00 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
function clause write_CSR(0x3C @ idx : bits(4), value) = { let idx = unsigned(0b01 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
function clause write_CSR(0x3D @ idx : bits(4), value) = { let idx = unsigned(0b10 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
function clause write_CSR(0x3E @ idx : bits(4), value) = { let idx = unsigned(0b11 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }

/* machine mode counters */
function clause write_CSR(0xB00, value) = { mcycle[(xlen - 1) .. 0] = value; value }
function clause write_CSR(0xB02, value) = { minstret_write = Some(value); value }
function clause write_CSR((0xB80, value) if xlen == 32) = { mcycle[63 .. 32] = value; value }
function clause write_CSR((0xB82, value) if xlen == 32) = { minstreth_write = Some(value); value }

/* Hardware Performance Monitoring machine mode counters */
function clause write_CSR((0b0011001 /* 0x320 */ @ index : bits(5), value) if unsigned(index) >= 3) = {
  let index = hpmidx_from_bits(index);
  write_mhpmevent(index, value);
  read_mhpmevent(index)
}
function clause write_CSR((0b1011000 /* 0xB00 */ @ index : bits(5), value) if unsigned(index) >= 3) = {
  let index = hpmidx_from_bits(index);
  write_mhpmcounter(index, value);
  read_mhpmcounter(index)
}
function clause write_CSR((0b1011100 /* 0xB80 */ @ index : bits(5), value) if xlen == 32 & unsigned(index) >= 3) = {
  let index = hpmidx_from_bits(index);
  write_mhpmcounterh(index, value);
  read_mhpmcounterh(index)
}

/* Sdtrig and Sdext registers */
function clause write_CSR(0x7a0, value) = { tselect = legalize_tselect(tselect, value); tselect }
function clause write_CSR(0x7a1, value) = {
  match unsigned(tselect){
    trig if 0 <= trig & trig < 6 => {
      write_tdata1_underlying(trig, legalize_tdata1(read_tdata1_underlying(trig), value));
      tdata1_write = true;
      read_tdata1_underlying(trig)
    },
    v => internal_error(__FILE__, __LINE__, "Currently unsupported tselect" ^ dec_str(v))
  }
}
function clause write_CSR(0x7a2, value) = {
  match unsigned(tselect){
    trig if 0 <= trig & trig < 6 => {
      write_tdata2_underlying(trig, legalize_tdata2(tdata2_underlying[trig], value));
      read_tdata2_underlying(trig)
    },
    v => internal_error(__FILE__, __LINE__, "Currently unsupported tselect" ^ dec_str(v))
  }
}
function clause write_CSR(0x7a4, value) = { legalize_tinfo(value).bits } // Read-only currently.
function clause write_CSR(0x7a5, value) = { tcontrol = legalize_tcontrol(tcontrol, value); tcontrol.bits }
function clause write_CSR(0x7b0, value) = { dcsr = legalize_dcsr(dcsr, value[31 .. 0]); zero_extend(dcsr.bits)}
function clause write_CSR(0x7b1, value) = { set_dpc(value) }
function clause write_CSR(0x7b2, value) = { set_dscratch0(value) }
function clause write_CSR(0x7b3, value) = { set_dscratch1(value) }

/* supervisor mode */
function clause write_CSR(0x100, value) = { set_xstatus(Supervisor, value); mstatus.bits }
function clause write_CSR(0x104, value) = { if inSmclicMode() then zeros() else { mie = legalize_sie(mie, mideleg, value); mie.bits } }
function clause write_CSR(0x105, value) = { set_stvec(value); get_stvec() }
function clause write_CSR(0x106, value) = { scounteren = legalize_scounteren(scounteren, value); zero_extend(scounteren.bits) }
function clause write_CSR(0x10A, value) = { set_senvcfg(value); senvcfg.bits }
function clause write_CSR(0x140, value) = { set_sscratch(value); get_sscratch() }
function clause write_CSR(0x141, value) = { set_sepc(value); get_sepc() }
function clause write_CSR(0x142, value) = { set_xcause(Supervisor, value); get_xcause(Supervisor).bits }
function clause write_CSR(0x143, value) = { stval = convertInvalidAddr(value); stval }
function clause write_CSR(0x144, value) = { if inSmclicMode() then zeros() else { mip = legalize_sip(mip, mideleg, value); mip.bits } }
function clause write_CSR(0x14D, value) = { stimecmp[(xlen - 1) .. 0] = value; stimecmp[xlen - 1 ..0] }
function clause write_CSR((0x15D, value) if xlen == 32) = { stimecmp[63 ..32] = value; stimecmp[63 .. 32] }
function clause write_CSR(0x180, value) = { satp = legalize_satp(cur_Architecture(), satp, value); satp }

/* user mode: seed (entropy source). writes are ignored */
function clause write_CSR(0x015, value) = write_seed_csr()

val handle_csr_op : (
  csreg,
  regidx,
  regidx,
  bool,
  csrop,
  bool,
  bool,
) -> Retired

function clause execute CSR(csr, rs1, rd, is_imm, op) = {
  // CSRRW[I] always writes. CSRRS[I] and CSRRC[I] write if the
  // source register (or immediate) is not x0 (or 0).
  let isWrite = op == CSRRW | rs1 != zeros();
  // CSRRS[I] and CSRRC[I] always read. CSRRW[I] reads if the destination
  // register is not x0.
  let isRead = op != CSRRW | rd != zeros();

  if not(check_CSR(csr, cur_privilege(), isWrite))
  then { handle_illegal(); RETIRE_FAIL }
  else if not(ext_check_CSR(csr, cur_privilege(), isWrite))
  then { ext_check_CSR_fail(); RETIRE_FAIL }
  else handle_csr_op(csr, rs1, rd, is_imm, op, isWrite, isRead)
}

function default_handle_csr_op(
  csr : csreg,
  rs1 : regidx,
  rd : regidx,
  is_imm : bool,
  op : csrop,
  isWrite : bool,
  isRead : bool,
) -> Retired = {
  let is_CSRRW_write = isWrite & (op == CSRRW) & not(is_imm);
  let write_val : xlenbits = if is_imm then zero_extend(rs1) else X(rs1);
  match (csr, xlen) {
    // Smclic nxti CSRs: mnxti, snxti, unxti.
    (0x345,  _) => { X(rd) = access_xnxti(csr, write_val, op, is_imm, isWrite, Machine); RETIRE_SUCCESS },
    (0x145,  _) => { X(rd) = access_xnxti(csr, write_val, op, is_imm, isWrite, Supervisor); RETIRE_SUCCESS },
    (0x045,  _) => { X(rd) = access_xnxti(csr, write_val, op, is_imm, isWrite, User); RETIRE_SUCCESS },
    _ => { /* standard CSRs */
      // Reading CSRs can have side effects and is not done in certain cases.
      let csr_val = if isRead then read_CSR(csr, write_val) else zeros();
      if isWrite then {
        let new_val : xlenbits = match op {
          CSRRW => write_val,
          CSRRS => csr_val | write_val,
          CSRRC => csr_val & ~(write_val)
        };
        let _ = write_CSR(csr, new_val);
      };
      X(rd) = csr_val;
      RETIRE_SUCCESS
    }
  };
}

mapping maybe_i : bool <-> string = {
  true  <-> "i",
  false <-> ""
}

mapping csr_mnemonic : csrop <-> string = {
  CSRRW <-> "csrrw",
  CSRRS <-> "csrrs",
  CSRRC <-> "csrrc"
}

mapping clause assembly = CSR(csr, rs1, rd, true, op)
  <-> csr_mnemonic(op) ^ "i" ^ spc() ^ reg_name(rd)  ^ sep() ^ csr_name_map(csr) ^ sep() ^ hex_bits_5(rs1)
mapping clause assembly = CSR(csr, rs1, rd, false, op)
  <-> csr_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ csr_name_map(csr) ^ sep() ^ reg_name(rs1)
