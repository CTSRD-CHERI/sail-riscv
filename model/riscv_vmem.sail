/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

// ****************************************************************
// Virtual memory address translation and memory protection,
// including PTWs (Page Table Walks) and TLBs (Translation Look-aside Buffers)
// Supported VM modes: Sv32, Sv39, Sv48.  TODO: Sv57

// STYLE NOTES:
//   PRIVATE items are used only within this VM code.
//   PUBLIC  items are invoked from other parts of sail-riscv.

// TLB NOTE:
// TLBs are not part of the RISC-V architecture specification.
// However, we model a simple TLB so that
// (1) we can meaningfully test SFENCE.VMA which is a no-op wihout TLBs;
// (2) we can greatly speed up simulation speed
//     (e.g., from 10s or minutes to few minutes for Linux boot)
// The TLB implementation is in a separate file: riscv_vmem_tlb.sail
// The code in this file is structured and commented so you can easily
// ignore TLB functionality at first reading.

// ****************************************************************
// Fields of virtual addresses

// PRIVATE: Extract full VPN field from VA
function vpns_of_va(sv_params : SV_Params,
                    va        : bits(64)) -> bits(64) = {
  let mask : bits(64) = zero_extend(ones(sv_params.va_size_bits));
  (va & mask) >> pagesize_bits
}

// PRIVATE: Extract VPN[level] from  VA
function vpn_j_of_va(sv_params : SV_Params,
                     va        : bits(64),
                     level     : PTW_Level) -> bits(64) = {
  let lsb  : range(0,63) = pagesize_bits + level * sv_params.vpn_size_bits;
  assert (lsb < xlen);
  let mask : bits(64) = zero_extend(ones(sv_params.vpn_size_bits));
  ((va >> lsb) & mask)
}

// PRIVATE: Extract offset within page from VA
function offset_of_va(va : bits(64)) -> bits(pagesize_bits) = va[pagesize_bits - 1 .. 0]

// Valid xlen-wide values containing virtual addrs must have upper
// bits equal to the MSB of the virtual address.
// Virtual address widths depend on the virtual memory mode.
// PRIVATE
function is_valid_vAddr(struct { va_size_bits, _ } : SV_Params,
                        vAddr                      : bits(64)) -> bool =
 vAddr == sign_extend(vAddr[va_size_bits - 1 .. 0])

// ****************************************************************
// Results of Page Table Walk (PTW)

// PRIVATE
union PTW_Result = {
  PTW_Success: (bits(64), bits(64), bits(64), nat, bool, ext_ptw),
  PTW_Failure: (PTW_Error, ext_ptw)
}

// ****************************************************************
// Page Table Walk (PTW)

register debug_ptw_address : option(bits(64)) = None()

// You call this to set a virtual address to log PTWs for. This can be
// set in the config JSON under debug_ptw_address.
function set_debug_ptw_address(vaddr : bits(64)) -> unit =
  debug_ptw_address = Some(vaddr)

// Utility function for PTW logging.
function print_ptw(message : string) -> unit =
  print_endline("[Sail PTW Hart " ^ dec_str(unsigned(mhartid)) ^ "] " ^ message)

// Note: 'pt_walk()' is recursive => needs separate 'val' decls

// PRIVATE
val pt_walk : (SV_Params,
               bits(64),                     // virtual addr
               AccessType(ext_access_type),  // Read/Write/ReadWrite/Execute
               Privilege,                    // User/Supervisor/Machine
               bool,                         // mstatus.MXR
               bool,                         // do_sum
               bits(64),                     // PT base addr
               PTW_Level,                    // tree level for this recursive call
               bool,                         // global translation,
               ext_ptw)                      // ext_ptw
              -> PTW_Result

function pt_walk(sv_params,
                 va,
                 ac,
                 priv,
                 mxr,
                 do_sum,
                 pt_base,
                 level,
                 global,
                 ext_ptw) = {
  let vpn_j      = vpn_j_of_va(sv_params, va, level);
  let pte_offset = vpn_j << sv_params.log_pte_size_bytes;
  let pte_addr   = pt_base + pte_offset;

  // In Sv32, physical addrs are actually 34 bits, not XLEN(=32) bits.
  // Below, 'pte_phys_addr' is XLEN bits because it's an arg to
  // 'mem_read_priv()' [riscv_mem.sail] where it's declared as xlenbits.
  // That def and this use need to be fixed together (TODO)
  let pte_phys_addr : xlenbits = pte_addr[(xlen - 1) .. 0];

  if debug_ptw_address == Some(va)
  then print_ptw(
    "  Level: " ^ dec_str(level) ^
    " Page Table Address: " ^ BitStr(pt_base) ^
    " Page Table Offset (bytes): " ^ BitStr(pte_offset) ^
    " Page Table Entry Address: " ^ BitStr(pte_phys_addr)
  );

  // Read this-level PTE from mem
  let mem_result = mem_read_priv(Read(Data),              // AccessType
                                 Supervisor,              // Privilege
                                 PMA,                     // No PBMT override.
                                 pte_phys_addr,
                                 2 ^ sv_params.log_pte_size_bytes, // 4/8 bytes.
                                 false,                   // aq
                                 false,                   // rl
                                 false);                  // res

  match mem_result {
    MemException(exc) => {
      if debug_ptw_address == Some(va)
      then print_ptw("  Error: Couldn't read PTE: " ^ to_str(exc));
      PTW_Failure(PTW_Access(), ext_ptw)
    },
    MemValue(pte)   => {
      if debug_ptw_address == Some(va)
      then print_ptw("  Read PTE: " ^ BitStr(pte));

      // Extend to 64 bits even on RV32 for simplicity.
      let pte : bits(64) = zero_extend(pte);

      let pte_flags = Mk_PTE_Flags(pte[7 .. 0]);
      let pte_ext   = ext_bits_of_PTE(sv_params, pte);
      if pte_is_invalid(pte_flags, pte_ext) then {
        if debug_ptw_address == Some(va)
        then print_ptw("  Error: PTE is invalid");
        PTW_Failure(PTW_Invalid_PTE(), ext_ptw)
      }
      else {
        let ppns : bits(64) = PPNs_of_PTE(sv_params, pte);
        let global'         = global | (pte_flags[G] == 0b1);
        if pte_is_ptr(pte_flags) then {
          // Non-Leaf PTE
          if level > 0 then {
            // follow the pointer to walk next level
            let pt_base' : bits(64) = ppns << pagesize_bits;
            let level'              = level - 1;
            pt_walk(sv_params, va, ac, priv, mxr, do_sum,
                    pt_base', level', global', ext_ptw)
          }
          else {
            // level 0 PTE, but contains a pointer instead of a leaf
            if debug_ptw_address == Some(va)
            then print_ptw("  Error: level 0 PTE is not a leaf");
            PTW_Failure(PTW_Invalid_PTE(), ext_ptw)
          }
        }
        else {
          // Leaf PTE
          let pte_check = check_PTE_permission(ac, priv, mxr, do_sum, pte_flags,
                                               pte_ext, ext_ptw);
          match pte_check {
            PTE_Check_Failure(ext_ptw, ext_ptw_fail) =>
              PTW_Failure(ext_get_ptw_error(ext_ptw_fail), ext_ptw),
            PTE_Check_Success(ext_ptw) =>
              if level > 0 then {
                // Superpage; construct mask for lower-level PPNs from the PTE
                let mask_bits = level * sv_params.pte_PPN_j_size_bits;
                // Clear the lowest `mask_bits` bits.
                let ppns_masked = (ppns >> mask_bits) << mask_bits;
                if not(ppns == ppns_masked) then {
                  // misaligned superpage mapping
                  if debug_ptw_address == Some(va)
                  then print_ptw("  Error: misaligned superpage");
                  PTW_Failure(PTW_Misaligned(), ext_ptw)
                }
                else {
                  // Compose final PA in superpage:
                  // Superpage PPN + lower VPNs + pagesize_bits page-offset
                  let mask : bits(64) = ~ (ones() << mask_bits);
                  let ppn = ppns | (vpns_of_va(sv_params, va) & mask);
                  let pa  = (ppn << pagesize_bits) | zero_extend(offset_of_va(va));
                  if debug_ptw_address == Some(va)
                  then print_ptw("  Success: " ^ bits_str(pa));
                  PTW_Success(pa, pte, pte_addr, level, global', ext_ptw)
                }
              }
              else {
                let pa = (ppns << pagesize_bits) | zero_extend(offset_of_va(va));
                if debug_ptw_address == Some(va)
                  then print_ptw("  Success: " ^ bits_str(pa));
                PTW_Success(pa, pte, pte_addr, level, global', ext_ptw)
              }
          }
        }
      }
    }
  }
}

// ****************************************************************
// Architectural SATP CSR

// PUBLIC: see also riscv_insts_zicsr.sail and other CSR-related files
register satp : xlenbits

// See riscv_sys_regs.sail for legalize_satp{32,64}().
// WARNING: those functions legalize Mode but not ASID?
// PUBLIC: invoked from writeCSR() to fixup WARL fields
function legalize_satp(a : Architecture,
                       o : xlenbits,        // previous value of satp
                       v : xlenbits)        // proposed new value of satp
                      -> xlenbits = {       // new legal value of satp
  if xlen == 32 then {
    // The slice and extend ops below are no-ops when xlen==32,
    // but appease the type-checker when xlen==64 (when this code is not executed!)
    let o32      : bits(32) = o[31 .. 0];
    let v32      : bits(32) = v[31 .. 0];
    let new_satp : bits(32) = legalize_satp32(a, o32, v32);
    zero_extend(new_satp);
  } else if xlen == 64 then {
    // The extend and truncate ops below are no-ops when xlen==64,
    // but appease the type-checker when xlen==32 (when this code is not executed!)
    let o64      : bits(64) = zero_extend(o);
    let v64      : bits(64) = zero_extend(v);
    let new_satp : bits(64) = legalize_satp64(a, o64, v64);
    truncate(new_satp, xlen)
  } else
    internal_error(__FILE__, __LINE__, "Unsupported xlen" ^ dec_str(xlen))
}

// ----------------
// Fields of SATP

// ASID is 9b in Sv32, 16b in Sv39/Sv48/Sv57: we use 16b for both
// PRIVATE
function satp_to_asid(satp_val : xlenbits) -> asidbits =
   if      xlen == 32 then zero_extend(Mk_Satp32(satp_val)[Asid])
   else if xlen == 64 then Mk_Satp64(satp_val)[Asid]
   else internal_error(__FILE__, __LINE__,
                       "Unsupported xlen" ^ dec_str(xlen))

// Result is 64b to cover both RV32 and RV64 addrs
// PRIVATE
function satp_to_PT_base(satp_val : xlenbits) -> bits(64) = {
  let ppn = if      xlen == 32 then zero_extend (64, Mk_Satp32(satp_val)[PPN])
            else if xlen == 64 then zero_extend (64, Mk_Satp64(satp_val)[PPN])
            else internal_error(__FILE__, __LINE__,
                                "Unsupported xlen" ^ dec_str(xlen));
  ppn << pagesize_bits
}

// Compute address translation mode from SATP register
// PRIVATE
function translationMode(priv : Privilege) -> SATPMode = {
  if priv == Machine then Sbare
  else {
    let arch = architecture(get_mstatus_SXL(mstatus));
    let arch : Architecture = match arch {
      Some(RV32) => RV32,
      Some(RV64) => RV64,
      // The model does not support modifying SXL currently so this cannot happen.
      _          => internal_error(__FILE__, __LINE__, "unsupported address translation arch")
    };
    let mbits : satp_mode = match arch {
      RV64 => {
        // Can't have an effective architecture of RV64 on RV32.
        assert(xlen >= 64);
        Mk_Satp64(satp)[Mode]
      },
      RV32 => 0b000 @ Mk_Satp32(satp[31..0])[Mode],
    };
    match satpMode_of_bits(arch, mbits) {
      Some(m) => m,
      // The model does not support modifying SXL currently so this cannot happen.
      None()  => internal_error(__FILE__, __LINE__, "invalid translation mode in satp")
    }
  }
}

// ****************************************************************
// VA to PA translation

// Write a Page Table Entry. Currently PTEs are passed around as 64 bits, even
// for Sv32 where they are actually 32 bits. `pte_size` is used to indicate
// the actual size in bytes that we want to write.
function write_pte forall 'n, 'n in {4, 8} . (
  paddr    : xlenbits,
  pte_size : int('n),
  pte      : bits(64),
) -> MemoryOpResult(bool) =
  mem_write_value_priv(PMA, paddr, pte_size, pte[pte_size * 8 - 1 .. 0], Supervisor, false, false, false)

// Result of address translation

// PUBLIC
union TR_Result('paddr : Type, 'failure : Type) = {
  TR_Address : ('paddr, PBMT, ext_ptw),
  TR_Failure : 'failure
}

// This function can be ignored on first reading since TLBs are not
// part of RISC-V architecture spec (see TLB_NOTE above).
// PRIVATE: translate on TLB hit, and maintenance of PTE in TLB
function translate_TLB_hit(sv_params : SV_Params,
                           asid      : asidbits,
                           ptb       : bits(64),
                           vAddr     : bits(64),
                           ac        : AccessType(ext_access_type),
                           priv      : Privilege,
                           mxr       : bool,
                           do_sum    : bool,
                           ext_ptw   : ext_ptw,
                           tlb_index : tlb_index_range,
                           ent       : TLB_Entry)
                          -> TR_Result(bits(64), PTW_Error) = {
  let pte       = ent.pte;
  let ext_pte   = ext_bits_of_PTE(sv_params, pte);
  // This should be impossible because there would have been a page fault
  // during translation.
  assert(ext_pte[PBMT] != 0b11);
  let pbmt = pbmt_enc(ext_pte[PBMT]);

  let pte_flags = Mk_PTE_Flags(pte[7 .. 0]);
  let pte_check = check_PTE_permission(ac, priv, mxr, do_sum, pte_flags,
                                       ext_pte,
                                       ext_ptw);
  match pte_check {
    PTE_Check_Failure(ext_ptw, ext_ptw_fail) =>
      TR_Failure(ext_get_ptw_error(ext_ptw_fail)),
    PTE_Check_Success(ext_ptw) =>
      match update_PTE_Bits(sv_params, pte, ac) {
        None()     => TR_Address(ent.pAddr | (vAddr & ent.vAddrMask), pbmt, ext_ptw),
        Some(pte') =>
          // See riscv_platform.sail
          if not(plat_enable_dirty_update()) then
            // pte needs dirty/accessed update but that is not enabled
            TR_Failure(PTW_PTE_Update())
          else {
            // Writeback the PTE (which has new A/D bits)
            let n_ent = {ent with pte=pte'};
            write_TLB(tlb_index, n_ent);
            let pte_phys_addr = ent.pteAddr[(xlen - 1) .. 0];

            match write_pte(pte_phys_addr, 2 ^ sv_params.log_pte_size_bytes, pte') {
              MemValue(_)     => (),
              MemException(e) => internal_error(__FILE__, __LINE__,
                                                "invalid physical address in TLB")
            };
            TR_Address(ent.pAddr | (vAddr & ent.vAddrMask), pbmt, ext_ptw)
          }
      }
  }
}

// PRIVATE: translate on TLB miss (do a page-table walk)
function translate_TLB_miss(sv_params : SV_Params,
                            asid      : asidbits,
                            ptb       : bits(64),
                            vAddr     : bits(64),
                            ac        : AccessType(ext_access_type),
                            priv      : Privilege,
                            mxr       : bool,
                            do_sum    : bool,
                            ext_ptw   : ext_ptw) -> TR_Result(bits(64), PTW_Error) = {

  if debug_ptw_address == Some(vAddr)
  then print_ptw("  Starting Page Table Walk for " ^ bits_str(vAddr));

  let initial_level = sv_params.levels - 1;
  let ptw_result    = pt_walk(sv_params, vAddr, ac, priv, mxr, do_sum,
                              ptb, initial_level, false, ext_ptw);
  match ptw_result {
    PTW_Failure(f, ext_ptw) => TR_Failure(f),
    PTW_Success(pAddr, pte, pteAddr, level, global, ext_ptw) => {
      let ext_pte   = ext_bits_of_PTE(sv_params, pte);

      // This should be impossible because there would have been a page fault
      // during translation.
      assert(ext_pte[PBMT] != 0b11);
      let pbmt = pbmt_enc(ext_pte[PBMT]);

      // Without TLBs, this 'match' expression can be replaced simply
      // by: 'TR_Address(pAddr, ext_ptw)'    (see TLB_NOTE above)
      match update_PTE_Bits(sv_params, pte, ac) {
        None() => {
          add_to_TLB(asid, vAddr, pAddr, pte, pteAddr, level, global,
                     sv_params.vpn_size_bits,
                     pagesize_bits);
          TR_Address(pAddr, pbmt, ext_ptw)
        },
        Some(pte') =>
          // See riscv_platform.sail
          if not(plat_enable_dirty_update()) then
            // pte needs dirty/accessed update but that is not enabled
            TR_Failure(PTW_PTE_Update())
          else {
            // Writeback the PTE (which has new A/D bits)
            let pte_phys_addr = pteAddr[(xlen - 1) .. 0];

            match write_pte(pte_phys_addr, 2 ^ sv_params.log_pte_size_bytes, pte') {
              MemValue(_) => {
                add_to_TLB(asid, vAddr, pAddr, pte', pteAddr, level, global,
                           sv_params.vpn_size_bits,
                           pagesize_bits);
                TR_Address(pAddr, pbmt, ext_ptw)
              },
              MemException(e) =>
                TR_Failure(PTW_Access())
            }
          }
        }
      }
    }
}

// val debug_detect_missing_fences = {c:"debug_detect_missing_fences"} : unit -> bool
// TODO:
function debug_detect_missing_fences() -> bool = false

// PRIVATE
function translate(sv_params : SV_Params,
                   asid      : asidbits,
                   ptb       : bits(64),
                   vAddr     : bits(64),
                   ac        : AccessType(ext_access_type),
                   priv      : Privilege,
                   mxr       : bool,
                   do_sum    : bool,
                   ext_ptw   : ext_ptw)
                  -> TR_Result(bits(64), PTW_Error) = {
  // On first reading, assume lookup_TLB returns None(), since TLBs
  // are not part of RISC-V archticture spec (see TLB NOTE above)
  match lookup_TLB(asid, vAddr) {
    Some(index, ent) => {
      let cached = translate_TLB_hit(sv_params, asid, ptb, vAddr, ac, priv,
                                     mxr, do_sum, ext_ptw, index, ent);

      // Optionally, always do the PTW and detect if it returns a different
      // value to the one from the TLB. If it does that means someone forgot
      // to add an `sfence.vma` somewhere. If it matches the TLB there may
      // still be a missing fence, so this check can have false negatives.
      if debug_detect_missing_fences() then {
        // Unfortunately this function mutates the TLB, but it shouldn't
        // matter - if cached == uncached then there should be no change.
        let uncached = translate_TLB_miss(sv_params, asid, ptb, vAddr, ac, priv,
                                          mxr, do_sum, ext_ptw);
        if cached != uncached then {
          print_endline("Full virtual address translation gave a different result\n" ^
                        "to the cached value from the TLB. This indicates a\n" ^
                        "missing 'sfence.vma' in the software, or possibly a\n" ^
                        "Page Table Entry being accidentally overwritten.\n\n" ^
                        "Virtual Address " ^ bits_str(vAddr));
          match cached {
            TR_Address(paddr, pb, _) => print_endline("Cached Result:   Physical Address: " ^ bits_str(paddr) ^ " PBMT " ^ to_str(pb)),
            TR_Failure(er) => print_endline("Cached Result:   " ^ to_str(er)),
          };
          match uncached {
            TR_Address(paddr, pb, _) => print_endline("Uncached Result: Physical Address: " ^ bits_str(paddr) ^ " PBMT " ^ to_str(pb)),
            TR_Failure(er) => print_endline("Uncached Result: " ^ to_str(er)),
          };
          // If needed, for even better debugging we can add a global
          // `register log_ptw : bool = false`, and then set it to true here
          // and call `translate_TLB_miss()` again. Then we can have full
          // logging of the PTW.
        };
        // Stop simulation.
        assert(cached == uncached);
      };
      cached
    },
    None()           => translate_TLB_miss(sv_params, asid, ptb, vAddr, ac, priv,
                                           mxr, do_sum, ext_ptw)
  }
}

// Top-level addr-translation function
// PUBLIC: invoked from instr-fetch and load/store/amo
function translateAddr(vAddr   : xlenbits,
                       ac      : AccessType(ext_access_type))
                      -> TR_Result(xlenbits, ExceptionType) = {
  if debug_ptw_address == Some(zero_extend(vAddr))
  then print_ptw("Translating " ^ bits_str(vAddr));

  // Internally the vmem code works with 64-bit values, whether xlen==32 or xlen==64
  // This 'extend' is a no-op when xlen==64 and extends when xlen==32
  let vAddr_64b : bits(64) = zero_extend(vAddr);
  // Effective privilege takes into account mstatus.PRV, mstatus.MPP
  // See riscv_sys_regs.sail for effectivePrivilege() and cur_privilege
  let effPriv   : Privilege = effectivePrivilege(ac, mstatus, cur_privilege());
  let mode      : SATPMode  = translationMode(effPriv);
  let (valid_va, sv_params) : (bool, SV_Params) = match mode {
    Sbare => {
        return TR_Address(vAddr, PMA, init_ext_ptw);
    },
    Sv32  => (true,                                 sv32_params),
    Sv39  => (is_valid_vAddr(sv39_params, vAddr_64b), sv39_params),
    Sv48  => (is_valid_vAddr(sv48_params, vAddr_64b), sv48_params),
    // Sv57 => (is_valid_vAddr(sv57_params, vAddr_64b), sv57_params),    // TODO
  };
  if not(valid_va) then {
    if debug_ptw_address == Some(zero_extend(vAddr))
    then print_ptw("  Error: address is not a valid virtual address");
    TR_Failure(translationException(ac, PTW_Invalid_Addr()))
  } else {
    let mxr               = mstatus[MXR] == 0b1;
    let do_sum            = mstatus[SUM] == 0b1;
    let asid   : asidbits = satp_to_asid(satp);
    let ptb    : bits(64) = satp_to_PT_base(satp);

    if debug_ptw_address == Some(zero_extend(vAddr))
    then print_ptw("  satp: " ^ bits_str(satp) ^ " (Page Table Base: " ^ bits_str(ptb) ^ ")");

    let tr_result1 = translate(sv_params,
                               asid,
                               ptb,
                               vAddr_64b,
                               ac, effPriv, mxr, do_sum,
                               init_ext_ptw);
    // Fixup result PA or exception
    match tr_result1 {
      TR_Address(pa, pbmt, ext_ptw) => TR_Address(truncate(pa, xlen), pbmt, ext_ptw),
      TR_Failure(f)  => TR_Failure(translationException(ac, f))
    }
  }
}

// ****************************************************************
// Initialize Virtual Memory state

// PUBLIC: invoked from init_model()
function reset_vmem() -> unit = init_TLB()

// ****************************************************************
