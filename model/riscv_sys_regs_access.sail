// This file contains functions for accessing some CSRs. They
// are in a separate file because they are overridden by CHERI.

/******************************* xTVEC[C] *******************************/

function get_mtvec() -> xlenbits = mtvec.bits
function get_stvec() -> xlenbits = read_stvec_utvec(stvec.bits)

function set_mtvec(value : xlenbits) -> unit = {
  let was_clic = inSmclicMode();
  mtvec = legalize_tvec(mtvec, convertInvalidAddr(value));

  // For backwards compatibility in systems supporting both CLINT and CLIC modes,
  // when switching to CLINT mode the new CLIC xcause state field (xpil) is zeroed.
  //
  // Also xinhv. See https://github.com/riscv/riscv-fast-interrupt/issues/418

  // TODO (CLIC): The spec also says these two conflicting things:
  //
  // 1. The other new CLIC xcause fields, xpp and xpie, appear as zero in the xcause
  //    CSR but the corresponding state bits in the mstatus register are not cleared.
  // 2. The mcause.mpp and mcause.mpie fields mirror the mstatus.mpp and mstatus.mpie
  //    fields, and are aliased into mcause to reduce context save/restore code.
  //
  // It seems like they have tried to fix this in the latest version of the
  // spec by adding extra vagueness.
  //
  // https://github.com/riscv/riscv-fast-interrupt/issues/405
  //
  if was_clic & not(inSmclicMode()) then {
    mcause[Xpil] = zeros();
    scause[Xpil] = zeros();
    mcause[Xinhv] = zeros();
    scause[Xinhv] = zeros();
  };
}

function set_stvec(value : xlenbits) -> unit = {
  stvec = legalize_tvec(stvec, convertInvalidAddr(value));
  // TODO (CLIC): Need to set mpil etc.
}

/******************************* xSCRATCH[C] *******************************/

function get_mscratch() -> xlenbits = mscratch

function set_mscratch(value : xlenbits) -> unit = {
  mscratch = value;
}

function get_sscratch() -> xlenbits = sscratch

function set_sscratch(value : xlenbits) -> unit = {
  sscratch = value;
}

/******************************* xEPC[C] *******************************/

function get_mepc() -> xlenbits = align_pc(mepc)

function set_mepc(value : xlenbits) -> unit = {
  mepc = legalize_xepc(convertInvalidAddr(value));
}

function get_sepc() -> xlenbits = align_pc(sepc)

function set_sepc(value : xlenbits) -> unit = {
  sepc = legalize_xepc(convertInvalidAddr(value));
}

/******************************* xenvcfg *******************************/

function set_menvcfg(v : bits(64)) -> unit = {
  menvcfg = legalize_menvcfg(menvcfg, mseccfg, v);
}

function set_senvcfg(v : xlenbits) -> unit = {
  senvcfg = legalize_senvcfg(senvcfg, menvcfg, v);
}

/******************************* mseccfg *******************************/

function set_mseccfg(v : bits(64)) -> unit = {
  mseccfg = legalize_mseccfg(mseccfg, v);
}
