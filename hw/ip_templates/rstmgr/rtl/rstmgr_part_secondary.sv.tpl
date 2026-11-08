// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Secondary partition of the split reset manager.
//
// The secondary partition hosts:
//  - the reset roots (por, lc source and sys source),
//  - the POR handling of each power domain,
//  - the leaf resets of its power domain whose clocks it receives.
// This partition drives the always-on resets directly. So they stay out of reset while the power
// domain of the primary partition is off.
`include "prim_assert.sv"

<%
from topgen.lib import Name
from ipgen.manager_split import (rstmgr_clocks, rstmgr_hosted_domains, rstmgr_is_array,
                                 rstmgr_out_domains, rstmgr_routed_rsts, rstmgr_rst_en_routed,
                                 rstmgr_routed_roots)
split_clks = rstmgr_clocks(clk_freqs, leaf_rsts, rst_ni)
secondary_clk_names = split_clks.secondary
primary_clk_names = split_clks.primary
aon_clks = split_clks.aon
# One error flag per leaf instance that this partition hosts (a shadowed leaf has two instances).
n_err = sum((2 if r['shadowed'] else 1) *
            len(rstmgr_hosted_domains(r, 'secondary'))
            for r in leaf_rsts)
%>\
module rstmgr_part_secondary
  import rstmgr_pkg::*;
  import prim_mubi_pkg::mubi4_t;
#(
  parameter bit SecCheck = 1,
  parameter int SecMaxSyncDelay = 2
) (
  // Secondary partition clocks
  input clk_i,
  input rst_ni,
% for clk in secondary_clk_names:
  input clk_${clk}_i,
% endfor
  input clk_por_i,
  input rst_por_ni,

  // Scan signals. They come from the DFT source in this partition's power domain.
  input prim_mubi_pkg::mubi4_t scanmode_i,
  input scan_rst_n_i,

  // POR input
  input [PowerDomains-1:0] por_n_i,

  // pwrmgr interface
  input pwrmgr_pkg::pwr_rst_req_t pwr_i,
  output pwrmgr_pkg::pwr_rst_rsp_t pwr_o,


  // Reset outputs of this partition
  output rstmgr_out_secondary_t resets_secondary_o,

  // inter-partition signalling
  output intraip_s2p_t intraip_s2p_o,
  input intraip_p2s_t intraip_p2s_i
);

  import prim_mubi_pkg::MuBi4False;
  import prim_mubi_pkg::MuBi4True;

  logic scan_rst_n;
  prim_mubi_pkg::mubi4_t scanmode;
  assign scan_rst_n = scan_rst_n_i;
  assign scanmode = scanmode_i;

  // The two structs below hold all the resets and reset asserted indications that this partition
  // generates. The routing at the end of the module selects the outputs from them.
  rstmgr_generated_secondary_t resets_generated;
  rstmgr_rst_en_generated_secondary_t rst_en_generated;
% if not rstmgr_routed_rsts(output_rsts, 'secondary'):

  // Nothing flows from the primary partition in this configuration.
  logic unused_intraip_p2s;
  assign unused_intraip_p2s = ^intraip_p2s_i;
% endif

  // receive POR and stretch
  // The por is at first stretched and synced on clk_aon
  // The rst_ni and pok_i input will be changed once AST is integrated
  logic [PowerDomains-1:0] rst_por_aon_n;
  // The roots and their reset asserted indications exist for every power domain. The por_aon reset
  // takes the roots and indications of its own power domains, in the shape of the structs (see
  // below).
  mubi4_t [PowerDomains-1:0] rst_en_por_aon;

  for (genvar i = 0; i < PowerDomains; i++) begin : gen_rst_por_aon

      // Declared as size 1 packed array to avoid FPV warning.
      prim_mubi_pkg::mubi4_t [0:0] por_scanmode;
      prim_mubi4_sync #(
        .NumCopies(1),
        .AsyncOn(0)
      ) u_por_scanmode_sync (
        .clk_i,
        .rst_ni,
        .mubi_i(scanmode),
        .mubi_o(por_scanmode)
      );

    if (i == DomainAonSel) begin : gen_rst_por_aon_normal
      rstmgr_por u_rst_por_aon (
        .clk_i(clk_aon_i),
        .rst_ni(por_n_i[i]),
        .scan_rst_ni(scan_rst_n),
        .scanmode_i(prim_mubi_pkg::mubi4_test_true_strict(por_scanmode[0])),
        .rst_no(rst_por_aon_n[i])
      );

      // reset asserted indication for alert handler
      prim_mubi4_sender #(
        .ResetValue(MuBi4True)
      ) u_prim_mubi4_sender (
        .clk_i(clk_aon_i),
        .rst_ni(rst_por_aon_n[i]),
        .mubi_i(MuBi4False),
        .mubi_o(rst_en_por_aon[i])
      );
    end else begin : gen_rst_por_domain
      logic rst_por_aon_premux;
      prim_flop_2sync #(
        .Width(1),
        .ResetValue('0)
      ) u_por_domain_sync (
        .clk_i(clk_aon_i),
        // do not release from reset if aon has not
        .rst_ni(rst_por_aon_n[DomainAonSel] & por_n_i[i]),
        .d_i(1'b1),
        .q_o(rst_por_aon_premux)
      );

      prim_clock_mux2 #(
        .NoFpgaBufG(1'b1)
      ) u_por_domain_mux (
        .clk0_i(rst_por_aon_premux),
        .clk1_i(scan_rst_n),
        .sel_i(prim_mubi_pkg::mubi4_test_true_strict(por_scanmode[0])),
        .clk_o(rst_por_aon_n[i])
      );

      // reset asserted indication for alert handler
      prim_mubi4_sender #(
        .ResetValue(MuBi4True)
      ) u_prim_mubi4_sender (
        .clk_i(clk_aon_i),
        .rst_ni(rst_por_aon_n[i]),
        .mubi_i(MuBi4False),
        .mubi_o(rst_en_por_aon[i])
      );
    end
  end
<%
por_aon = [r for r in output_rsts if r['name'] == 'por_aon'][0]
por_aon_sel = lambda d: f"[Domain{d}Sel]" if rstmgr_is_array(por_aon['domains'], power_domains) else ""
por_aon_unused = [d for d in power_domains if d not in por_aon['domains']]
%>\
% for d in por_aon['domains']:
  assign resets_generated.rst_por_aon_n${por_aon_sel(d)} = rst_por_aon_n[Domain${d}Sel];
  assign rst_en_generated.por_aon${por_aon_sel(d)} = rst_en_por_aon[Domain${d}Sel];
% endfor
% if por_aon_unused:
  // In these power domains, nothing uses the reset asserted indication of por_aon.
  logic unused_rst_en_por_aon;
  assign unused_rst_en_por_aon = ^{${', '.join(f"rst_en_por_aon[Domain{d}Sel]" for d in por_aon_unused)}};
% endif

  logic clk_por;
  prim_clock_buf #(
    .NoFpgaBuf(1'b1)
  ) u_por_clk_buf (
    .clk_i(clk_por_i),
    .clk_o(clk_por)
  );

  logic rst_por_n;
  prim_clock_buf #(
    .NoFpgaBuf(1'b1)
  ) u_por_rst_buf (
    .clk_i(rst_por_ni),
    .clk_o(rst_por_n)
  );

  ////////////////////////////////////////////////////
  // Source resets in the system                    //
  // These are hardcoded and not directly used.     //
  // Instead they act as async reset roots.         //
  ////////////////////////////////////////////////////

  // The two source reset modules are chained together.  The output of one is fed into the
  // the second.  This ensures that if upstream resets for any reason, the associated downstream
  // reset will also reset.

  logic [PowerDomains-1:0] rst_lc_src_n;
  logic [PowerDomains-1:0] rst_sys_src_n;

  // Declared as size 1 packed array to avoid FPV warning.
  prim_mubi_pkg::mubi4_t [0:0] rst_ctrl_scanmode;
  prim_mubi4_sync #(
    .NumCopies(1),
    .AsyncOn(0)
  ) u_ctrl_scanmode_sync (
    .clk_i (clk_por),
    .rst_ni (rst_por_n),
    .mubi_i(scanmode),
    .mubi_o(rst_ctrl_scanmode)
  );

  // lc reset sources
  rstmgr_ctrl u_lc_src (
    .clk_i (clk_por),
    .scanmode_i(prim_mubi_pkg::mubi4_test_true_strict(rst_ctrl_scanmode[0])),
    .scan_rst_ni(scan_rst_n),
    .rst_req_i(pwr_i.rst_lc_req),
    .rst_parent_ni(rst_por_aon_n),
    .rst_no(rst_lc_src_n)
  );

  // sys reset sources
  rstmgr_ctrl u_sys_src (
    .clk_i (clk_por),
    .scanmode_i(prim_mubi_pkg::mubi4_test_true_strict(rst_ctrl_scanmode[0])),
    .scan_rst_ni(scan_rst_n),
    .rst_req_i(pwr_i.rst_sys_req),
    .rst_parent_ni(rst_por_aon_n),
    .rst_no(rst_sys_src_n)
  );

  assign pwr_o.rst_lc_src_n = rst_lc_src_n;
  assign pwr_o.rst_sys_src_n = rst_sys_src_n;

  ////////////////////////////////////////////////////
  // Errors of this partition's leaf resets         //
  ////////////////////////////////////////////////////
% if n_err:
  logic [${n_err-1}:0] cnsty_chk_errs;
  logic [${n_err-1}:0] fsm_errs;
% endif

  ////////////////////////////////////////////////////
  // Leaf resets of the secondary partition         //
  // The primary partition generates every other    //
  // leaf reset.                                    //
  ////////////////////////////////////////////////////
<% err_idx = 0 %>\
% for rst in leaf_rsts:
<%
names = [rst['name']]
if rst['shadowed']:
  names.append(f"{rst['name']}_shadowed")
hosted = rstmgr_hosted_domains(rst, 'secondary')
assert not hosted or rst['clock'] in secondary_clk_names, (
    f"reset {rst['name']} is driven by the secondary partition, which has no port for its clock {rst['clock']}")
arr = bool(hosted) and rstmgr_is_array(hosted, power_domains)
# All clocks of this partition, the always-on one included, are input ports.
leaf_clk = f"clk_{rst['clock']}_i"
%>\
  % if hosted:
  // Generating resets for ${names[0]}
  // Power Domains: ${rst['domains']}, hosted in this partition: ${hosted}
  // Shadowed: ${rst['shadowed']}
    % for name in names:
<% rst_name_camel = Name.to_camel_case(name) %>\
      % for domain in hosted:
<% sel = f"[Domain{domain}Sel]" if arr else "" %>\
  rstmgr_leaf_rst #(
        % if names[0]==rst_ni:
    .SecCheck(0),
        % else:
    .SecCheck(SecCheck),
        % endif
    .SecMaxSyncDelay(SecMaxSyncDelay),
        % if rst['sw']:
    .SwRstReq(1'b1)
        % else:
    .SwRstReq(1'b0)
        % endif
  ) u_d${domain.lower()}_${name} (
    .clk_i,
    .rst_ni,
    .leaf_clk_i(${leaf_clk}),
    .parent_rst_ni(rst_${rst['parent']}_n[Domain${domain}Sel]),
<% assert not rst['sw'], f"secondary leaf {rst['name']} cannot be software resettable" %>\
    .sw_rst_req_ni(1'b1),
    .scan_rst_ni(scan_rst_n),
    .scanmode_i(scanmode),
    .rst_en_o(rst_en_generated.${name}${sel}),
    .leaf_rst_o(resets_generated.rst_${name}_n${sel}),
    .err_o(cnsty_chk_errs[${err_idx}]),
    .fsm_err_o(fsm_errs[${err_idx}])
  );
<% err_idx += 1 %>\
        % if names[0]!=rst_ni:
  // The assertion uses _ERR rather than _ALERT on purpose, as this partition has no alert. The FSM
  // error leaves this partition through intraip_s2p_o.fsm_err, and the primary partition turns it
  // into its fatal alert.
  if (SecCheck) begin : gen_d${domain.lower()}_${name}_assert
  `ASSERT_PRIM_FSM_ERROR_TRIGGER_ERR(
    D${domain.capitalize()}${rst_name_camel}FsmCheck_A,
    u_d${domain.lower()}_${name}.gen_rst_chk.u_rst_chk.u_state_regs,
    intraip_s2p_o.fsm_err)
  end
        % endif
      % endfor
    % endfor
  % endif
% endfor

  ////////////////////////////////////////////////////
  // Signalling to the primary partition            //
  ////////////////////////////////////////////////////
% for root, domain in rstmgr_routed_roots(leaf_rsts):
  assign intraip_s2p_o.rst_${root}_n_${domain.lower()} = rst_${root}_n[Domain${domain}Sel];
% endfor
  assign intraip_s2p_o.pwr                  = pwr_i;
  // The store of the ERR_CODE CSR, whose register type is hwext. One bit per field:
  //  - REG_INTG_ERR: the integrity error of the register file.
  //  - RESET_CONSISTENCY_ERR: the consistency errors of the leaves of both partitions.
  //  - FSM_ERR: the FSM errors of the leaves of both partitions.
  // They are kept here, in the secondary partition, as it is always in the Aon power domain. This
  // keeps them through a deep sleep cycle, including an error detected while entering deep sleep,
  // as long as the checkers' clock runs until their resets assert. Tampering with the Aon resets is
  // always captured.
  // Note: the reset that an escalation triggers must clear these bits, or the alert would fire
  // again after the escalation.
  logic cnsty_chk_err, fsm_err;
  logic reg_intg_err_q, cnsty_chk_err_q, fsm_err_q;
% if n_err:
  assign cnsty_chk_err = |cnsty_chk_errs || intraip_p2s_i.cnsty_chk_err;
  assign fsm_err       = |fsm_errs || intraip_p2s_i.fsm_err;
% else:
  assign cnsty_chk_err = intraip_p2s_i.cnsty_chk_err;
  assign fsm_err       = intraip_p2s_i.fsm_err;
% endif

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_intg_err_q  <= 1'b0;
      cnsty_chk_err_q <= 1'b0;
      fsm_err_q       <= 1'b0;
    end else begin
      reg_intg_err_q  <= reg_intg_err_q || intraip_p2s_i.reg_intg_err;
      cnsty_chk_err_q <= cnsty_chk_err_q || cnsty_chk_err;
      fsm_err_q       <= fsm_err_q || fsm_err;
    end
  end

  assign intraip_s2p_o.reg_intg_err           = reg_intg_err_q;
  assign intraip_s2p_o.cnsty_chk_err          = cnsty_chk_err_q;
  assign intraip_s2p_o.fsm_err                = fsm_err_q;

  `ASSERT(RegIntgErrRecordSticky_A, reg_intg_err_q |=> reg_intg_err_q)
  `ASSERT(CnstyChkErrRecordSticky_A, cnsty_chk_err_q |=> cnsty_chk_err_q)
  `ASSERT(FsmErrRecordSticky_A, fsm_err_q |=> fsm_err_q)
% if not n_err:
  // Without leaves, this partition does not use the parameters of the leaves, or the clocks that
  // only leaves use.
  logic unused_leaf_cfg;
  assign unused_leaf_cfg = ^{SecCheck, SecMaxSyncDelay${''.join(f", clk_{c}_i" for c in secondary_clk_names if c != 'aon')}};
% endif

  ////////////////////////////////////////////////////
  // Assertions                                     //
  ////////////////////////////////////////////////////
  `ASSERT_KNOWN(PwrKnownO_A,         pwr_o         )
  ////////////////////////////////////////////////////
  // Routing. This partition outputs the resets that its power domain uses.
  ////////////////////////////////////////////////////
% for rst in output_rsts:
<%
names = [rst['name']] + ([rst['name'] + '_shadowed'] if rst['shadowed'] else [])
out_doms = rstmgr_out_domains(rst, 'secondary')
prod_doms = rstmgr_hosted_domains(rst, 'secondary')
other_out = rstmgr_out_domains(rst, 'primary')
out_arr = bool(out_doms) and rstmgr_is_array(out_doms, power_domains)
prod_arr = bool(prod_doms) and rstmgr_is_array(prod_doms, power_domains)
%>\
  % for n in names:
    % for d in out_doms:
<% osel = f"[Domain{d}Sel]" if out_arr else ""
psel = f"[Domain{d}Sel]" if prod_arr else "" %>\
<% lhs = f"resets_secondary_o.rst_{n}_n{osel}"
rhs = f"resets_generated.rst_{n}_n{psel}" if d in prod_doms else f"intraip_p2s_i.rst_{n}_n_{d.lower()}" %>\
      % if len(f"  assign {lhs} = {rhs};") <= 100:
  assign ${lhs} = ${rhs};
      % else:
  assign ${lhs} =
      ${rhs};
      % endif
    % endfor
    % for d in prod_doms:
      % if d in other_out:
  assign intraip_s2p_o.rst_${n}_n_${d.lower()} = resets_generated.rst_${n}_n${f"[Domain{d}Sel]" if prod_arr else ""};
      % endif
    % endfor
  % endfor
% endfor

  // The reset asserted indications that this partition generates go to the primary partition,
  // which outputs them.
% for f, n, d in rstmgr_rst_en_routed(output_rsts):
<% rst = next(r for r in output_rsts if n in (r['name'], r['name'] + '_shadowed'))
hosted = rstmgr_hosted_domains(rst, 'secondary')
psel = f"[Domain{d}Sel]" if rstmgr_is_array(hosted, power_domains) else "" %>\
  assign intraip_s2p_o.${f} = rst_en_generated.${n}${psel};
% endfor

  `ASSERT_KNOWN(ResetsKnownO_A,      resets_secondary_o      )
  `ASSERT_KNOWN(IntraipKnownO_A,   intraip_s2p_o)
endmodule // rstmgr_part_secondary
