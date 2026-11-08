// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Primary partition of the split reset manager.
//
// The primary partition hosts:
//  - the register file and the alerts,
//  - the crash dump capture (ALERT_INFO and CPU_INFO),
//  - the RESET_INFO logic,
//  - the leaf resets that the secondary partition does not host.

`include "prim_assert.sv"

<%
from topgen.lib import Name
from ipgen.manager_split import (rstmgr_clocks, rstmgr_hosted_domains, rstmgr_is_array,
                                 rstmgr_out_domains, rstmgr_routed_roots, rstmgr_routed_rsts)
split_clks = rstmgr_clocks(clk_freqs, leaf_rsts, rst_ni)
secondary_clk_names = split_clks.secondary
primary_clk_names = split_clks.primary
aon_clks = split_clks.aon
# One error flag per leaf instance that this partition hosts (a shadowed leaf has two instances).
n_err = sum((2 if r['shadowed'] else 1) *
            len(rstmgr_hosted_domains(r, 'primary'))
            for r in leaf_rsts)
%>\

// This top level controller is fairly hardcoded right now, but will be switched to a template
module rstmgr_part_primary
  import rstmgr_pkg::*;
  import rstmgr_reg_pkg::*;
  import prim_mubi_pkg::mubi4_t;
#(
  parameter logic [NumAlerts-1:0] AlertAsyncOn = {NumAlerts{1'b1}},
  // Number of cycles a differential skew is tolerated on the alert signal
  parameter int unsigned AlertSkewCycles = 1,
  parameter bit SecCheck = 1,
  parameter int SecMaxSyncDelay = 2
) (
  // Primary module clocks
  input clk_i,
  input rst_ni,
% for clk in primary_clk_names:
  input clk_${clk}_i,
% endfor
  input clk_por_i,
  // This partition buffers the por reset, and uses it with the por clock for the register block.
  input rst_por_ni,

  // Bus Interface
  input tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  // Alerts
  input  prim_alert_pkg::alert_rx_t [NumAlerts-1:0] alert_rx_i,
  output prim_alert_pkg::alert_tx_t [NumAlerts-1:0] alert_tx_o,

  // software initiated reset request
  output mubi4_t sw_rst_req_o,

  // Interface to alert handler
  input alert_handler_pkg::alert_crashdump_t alert_dump_i,

  // Interface to cpu crash dump
  input rv_core_ibex_pkg::cpu_crash_dump_t cpu_dump_i,

  // dft bypass
  input scan_rst_ni,
  // SEC_CM: SCAN.INTERSIG.MUBI
  input prim_mubi_pkg::mubi4_t scanmode_i,

  // Reset asserted indications going to alert handler
  output rstmgr_rst_en_primary_t rst_en_o,

  // reset outputs
% for intf in export_rsts:
  output rstmgr_${intf}_out_t resets_${intf}_o,
% endfor
  output rstmgr_out_primary_t resets_o,

  // inter-partition signalling
  input intraip_s2p_t intraip_s2p_i,
  output intraip_p2s_t intraip_p2s_o
);

  import prim_mubi_pkg::MuBi4False;
  import prim_mubi_pkg::MuBi4True;

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

  // The two structs below hold all the resets and reset asserted indications that this partition
  // generates. The routing at the end of the module selects the outputs from them.
  rstmgr_generated_primary_t resets_generated;
  rstmgr_rst_en_generated_primary_t rst_en_generated;

  ////////////////////////////////////////////////////
  // Register Interface                             //
  ////////////////////////////////////////////////////

  rstmgr_reg_pkg::rstmgr_reg2hw_t reg2hw;
  rstmgr_reg_pkg::rstmgr_hw2reg_t hw2reg;

  logic reg_intg_err;
  // SEC_CM: BUS.INTEGRITY
  // SEC_CM: SW_RST.CONFIG.REGWEN, DUMP_CTRL.CONFIG.REGWEN
  rstmgr_reg_top u_reg (
    .clk_i,
    .rst_ni,
    .clk_por_i  (clk_por),
    .rst_por_ni (rst_por_n),
    .tl_i,
    .tl_o,
    .reg2hw,
    .hw2reg,
    .intg_err_o(reg_intg_err)
  );


  ////////////////////////////////////////////////////
  // Errors                                         //
  ////////////////////////////////////////////////////

  // consistency check errors
% if n_err:
  logic [${n_err-1}:0] cnsty_chk_errs;
  logic [${n_err-1}:0] fsm_errs;
% endif

  // consistency sparse fsm errors

  // ERR_CODE is external: the register file keeps no state for it. This partition's errors go to
  // the secondary partition, which keeps the record of all of them in the always-on power domain.
  // ERR_CODE and the alerts read that record.
  assign intraip_p2s_o.reg_intg_err  = reg_intg_err;
  assign intraip_p2s_o.cnsty_chk_err = ${"|cnsty_chk_errs" if n_err else "1'b0"};
  assign intraip_p2s_o.fsm_err       = ${"|fsm_errs" if n_err else "1'b0"};

  assign hw2reg.err_code.reg_intg_err.d          = intraip_s2p_i.reg_intg_err;
  assign hw2reg.err_code.reset_consistency_err.d = intraip_s2p_i.cnsty_chk_err;
  assign hw2reg.err_code.fsm_err.d               = intraip_s2p_i.fsm_err;
  ////////////////////////////////////////////////////
  // Alerts                                         //
  ////////////////////////////////////////////////////
  logic [NumAlerts-1:0] alert_test, alerts;

  // All of these are fatal alerts
  assign alerts[0] = intraip_s2p_i.reg_intg_err | intraip_s2p_i.fsm_err;

  assign alerts[1] = intraip_s2p_i.cnsty_chk_err;

  assign alert_test = {
    reg2hw.alert_test.fatal_cnsty_fault.q & reg2hw.alert_test.fatal_cnsty_fault.qe,
    reg2hw.alert_test.fatal_fault.q & reg2hw.alert_test.fatal_fault.qe
  };

  for (genvar i = 0; i < NumAlerts; i++) begin : gen_alert_tx
    prim_alert_sender #(
      .AsyncOn(AlertAsyncOn[i]),
      .SkewCycles(AlertSkewCycles),
      .IsFatal(1'b1)
    ) u_prim_alert_sender (
      .clk_i,
      .rst_ni,
      .alert_test_i  ( alert_test[i] ),
      .alert_req_i   ( alerts[i]     ),
      .alert_ack_o   (               ),
      .alert_state_o (               ),
      .alert_rx_i    ( alert_rx_i[i] ),
      .alert_tx_o    ( alert_tx_o[i] )
    );
  end

  ////////////////////////////////////////////////////
  // Source resets in the system                    //
  // These are hardcoded and not directly used.     //
  // Instead they act as async reset roots.         //
  ////////////////////////////////////////////////////

  // The secondary partition generates the source resets (lc and sys).


  ////////////////////////////////////////////////////
  // leaf reset in the system                       //
  // These should all be generated                  //
  ////////////////////////////////////////////////////
  // To simplify generation, each reset generates all associated power domain outputs.
  // If a reset does not support a particular power domain, that reset is always hard-wired to 0.

<% err_idx = 0 %>\
  // The roots that the leaves here have as parents come from the secondary partition. Each gets
  // a local net, so a leaf connects to a plain signal rather than to a field of intraip_s2p_i. A
  // force on a leaf's parent reset in the DV then reaches an ordinary net, as before the split.
% for root, domain in rstmgr_routed_roots(leaf_rsts):
  logic rst_${root}_n_${domain.lower()};
  assign rst_${root}_n_${domain.lower()} = intraip_s2p_i.rst_${root}_n_${domain.lower()};
% endfor

% for rst in leaf_rsts:
<%
names = [rst['name']]
if rst['shadowed']:
  names.append(f"{rst['name']}_shadowed")
hosted = rstmgr_hosted_domains(rst, 'primary')
arr = bool(hosted) and rstmgr_is_array(hosted, power_domains)
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
    .parent_rst_ni(rst_${rst['parent']}_n_${domain.lower()}),
        % if rst['sw']:
    .sw_rst_req_ni(reg2hw.sw_rst_ctrl_n[${name.upper()}].q),
        % else:
    .sw_rst_req_ni(1'b1),
        % endif
    .scan_rst_ni,
    .scanmode_i,
    .rst_en_o(rst_en_generated.${name}${sel}),
    .leaf_rst_o(resets_generated.rst_${name}_n${sel}),
    .err_o(cnsty_chk_errs[${err_idx}]),
    .fsm_err_o(fsm_errs[${err_idx}])
  );
<% err_idx += 1 %>\
        % if names[0]!=rst_ni:
  if (SecCheck) begin : gen_d${domain.lower()}_${name}_assert
  `ASSERT_PRIM_FSM_ERROR_TRIGGER_ALERT(
    D${domain.capitalize()}${rst_name_camel}FsmCheck_A,
    u_d${domain.lower()}_${name}.gen_rst_chk.u_rst_chk.u_state_regs,
    alert_tx_o[0])
  end
        % endif
      % endfor
    % endfor
  % endif
% endfor

  ////////////////////////////////////////////////////
  // Reset info construction                        //
  ////////////////////////////////////////////////////

  logic rst_hw_req;
  logic rst_low_power;
  logic pwrmgr_rst_req;

  // there is a valid reset request from pwrmgr
  assign pwrmgr_rst_req = |intraip_s2p_i.pwr.rst_lc_req || |intraip_s2p_i.pwr.rst_sys_req;

  // a reset reason is only valid if the related processing element is also reset.
  // In the future, if ever there are multiple processing elements, this code here
  // must be updated to account for each individual core.
  assign rst_hw_req    = pwrmgr_rst_req &
                         (intraip_s2p_i.pwr.reset_cause == pwrmgr_pkg::HwReq);
  assign rst_low_power = pwrmgr_rst_req &
                         (intraip_s2p_i.pwr.reset_cause == pwrmgr_pkg::LowPwrEntry);

  // software initiated reset request
  assign sw_rst_req_o = prim_mubi_pkg::mubi4_t'(reg2hw.reset_req.q);

  // when pwrmgr reset request is received (reset is imminent), clear software
  // request so we are not in an infinite reset loop.
  assign hw2reg.reset_req.de = pwrmgr_rst_req;
  assign hw2reg.reset_req.d  = prim_mubi_pkg::MuBi4False;

  // Only sw is allowed to clear a reset reason, hw is only allowed to set it.
  assign hw2reg.reset_info.low_power_exit.d  = 1'b1;
  assign hw2reg.reset_info.low_power_exit.de = rst_low_power;

  // software issued request triggers the same response as hardware, although it is
  // accounted for differently.
  assign hw2reg.reset_info.sw_reset.d = prim_mubi_pkg::mubi4_test_true_strict(sw_rst_req_o) |
                                        reg2hw.reset_info.sw_reset.q;
  assign hw2reg.reset_info.sw_reset.de = rst_hw_req;

  // HW reset requests most likely will be multi-bit, so OR in whatever reasons
  // that are already set.
  assign hw2reg.reset_info.hw_req.d  = intraip_s2p_i.pwr.rstreqs |
                                       reg2hw.reset_info.hw_req.q;
  assign hw2reg.reset_info.hw_req.de = rst_hw_req;

  ////////////////////////////////////////////////////
  // Crash info capture                             //
  ////////////////////////////////////////////////////

  logic dump_capture;
  assign dump_capture =  rst_hw_req | rst_low_power;

  // halt dump capture once we hit particular conditions
  logic dump_capture_halt;
  assign dump_capture_halt = rst_hw_req;

  rstmgr_crash_info #(
    .CrashDumpWidth($bits(alert_handler_pkg::alert_crashdump_t))
  ) u_alert_info (
    .clk_i(clk_por),
    .rst_ni(rst_por_n),
    .dump_i(alert_dump_i),
    .dump_capture_i(dump_capture & reg2hw.alert_info_ctrl.en.q),
    .slot_sel_i(reg2hw.alert_info_ctrl.index.q),
    .slots_cnt_o(hw2reg.alert_info_attr.d),
    .slot_o(hw2reg.alert_info.d)
  );

  rstmgr_crash_info #(
    .CrashDumpWidth($bits(rv_core_ibex_pkg::cpu_crash_dump_t))
  ) u_cpu_info (
    .clk_i(clk_por),
    .rst_ni(rst_por_n),
    .dump_i(cpu_dump_i),
    .dump_capture_i(dump_capture & reg2hw.cpu_info_ctrl.en.q),
    .slot_sel_i(reg2hw.cpu_info_ctrl.index.q),
    .slots_cnt_o(hw2reg.cpu_info_attr.d),
    .slot_o(hw2reg.cpu_info.d)
  );

  // once dump is captured, no more information is captured until
  // re-enabled by software.
  assign hw2reg.alert_info_ctrl.en.d  = 1'b0;
  assign hw2reg.alert_info_ctrl.en.de = dump_capture_halt;
  assign hw2reg.cpu_info_ctrl.en.d  = 1'b0;
  assign hw2reg.cpu_info_ctrl.en.de = dump_capture_halt;

  ////////////////////////////////////////////////////
  // Exported resets                                //
  ////////////////////////////////////////////////////
% for intf, eps in export_rsts.items():
  % for ep, rsts in eps.items():
    % for rst in rsts:
<% assert len(rstmgr_hosted_domains(next(r for r in output_rsts if r['name'] == rst['name']), 'primary')) == len(power_domains), f"exported reset {rst['name']} must be hosted by the primary partition for every power domain" %>\
  assign resets_${intf}_o.rst_${intf}_${ep}_${rst['name']}_n = resets_generated.rst_${rst['name']}_n;
    % endfor
  % endfor
% endfor




  ////////////////////////////////////////////////////
  // Assertions                                     //
  ////////////////////////////////////////////////////

  `ASSERT_INIT(ParameterMatch_A, NumHwResets == pwrmgr_pkg::HwResetWidth)

  // when upstream resets, downstream must also reset

  // output known asserts
  `ASSERT_KNOWN(TlDValidKnownO_A,    tl_o.d_valid  )
  `ASSERT_KNOWN(TlAReadyKnownO_A,    tl_o.a_ready  )
  `ASSERT_KNOWN(AlertsKnownO_A,      alert_tx_o    )
  ////////////////////////////////////////////////////
  // Routing. This partition outputs the resets that its power domain uses.
  ////////////////////////////////////////////////////
% for rst in output_rsts:
<%
names = [rst['name']] + ([rst['name'] + '_shadowed'] if rst['shadowed'] else [])
out_doms = rstmgr_out_domains(rst, 'primary')
prod_doms = rstmgr_hosted_domains(rst, 'primary')
other_out = rstmgr_out_domains(rst, 'secondary')
out_arr = bool(out_doms) and rstmgr_is_array(out_doms, power_domains)
prod_arr = bool(prod_doms) and rstmgr_is_array(prod_doms, power_domains)
%>\
  % for n in names:
    % for d in out_doms:
<% osel = f"[Domain{d}Sel]" if out_arr else ""
psel = f"[Domain{d}Sel]" if prod_arr else "" %>\
<% lhs = f"resets_o.rst_{n}_n{osel}"
rhs = f"resets_generated.rst_{n}_n{psel}" if d in prod_doms else f"intraip_s2p_i.rst_{n}_n_{d.lower()}" %>\
      % if len(f"  assign {lhs} = {rhs};") <= 100:
  assign ${lhs} = ${rhs};
      % else:
  assign ${lhs} =
      ${rhs};
      % endif
    % endfor
    % for d in prod_doms:
      % if d in other_out:
  assign intraip_p2s_o.rst_${n}_n_${d.lower()} = resets_generated.rst_${n}_n${f"[Domain{d}Sel]" if prod_arr else ""};
      % endif
    % endfor
  % endfor
% endfor

  ////////////////////////////////////////////////////
  // Routing. This partition outputs all the reset asserted indications.
  ////////////////////////////////////////////////////
% for rst in output_rsts:
<%
names = [rst['name']] + ([rst['name'] + '_shadowed'] if rst['shadowed'] else [])
prod_doms = rstmgr_hosted_domains(rst, 'primary')
out_arr = rstmgr_is_array(rst['domains'], power_domains)
prod_arr = bool(prod_doms) and rstmgr_is_array(prod_doms, power_domains)
%>\
  % for n in names:
    % for d in rst['domains']:
<% osel = f"[Domain{d}Sel]" if out_arr else ""
psel = f"[Domain{d}Sel]" if prod_arr else "" %>\
      % if d in prod_doms:
  assign rst_en_o.${n}${osel} = rst_en_generated.${n}${psel};
      % else:
  assign rst_en_o.${n}${osel} = intraip_s2p_i.rst_en_${n}_${d.lower()};
      % endif
    % endfor
  % endfor
% endfor

  `ASSERT_KNOWN(ResetsKnownO_A,      resets_o      )
  `ASSERT_KNOWN(RstEnKnownO_A,       rst_en_o      )
% for intf in export_rsts:
  `ASSERT_KNOWN(${intf.capitalize()}ResetsKnownO_A, resets_${intf}_o )
% endfor

  // Alert assertions for reg_we onehot check
  `ASSERT_PRIM_REG_WE_ONEHOT_ERROR_TRIGGER_ALERT(RegWeOnehotCheck_A, u_reg, alert_tx_o[0])
endmodule // rstmgr_part_primary
