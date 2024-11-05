register dpc       : xlenbits
register dscratch0 : xlenbits // No legalisation needed.
register dscratch1 : xlenbits // No legalisation needed.

function set_dpc(value : xlenbits) -> xlenbits = { // For CHERI compatibility
  let target = legalize_xepc(convertInvalidAddr(value)); // Legalisation of dpc is like mepc
  dpc = target;
  dpc
}

function set_dscratch0(value : xlenbits) -> xlenbits = { // For CHERI compatibility
  dscratch0 = value;
  dscratch0
}

function set_dscratch1(value : xlenbits) -> xlenbits = { // For CHERI compatibility
  dscratch1 = value;
  dscratch1
}

function get_dpc() -> xlenbits = dpc
function get_dscratch0() -> xlenbits = dscratch0
function get_dscratch1() -> xlenbits = dscratch1
