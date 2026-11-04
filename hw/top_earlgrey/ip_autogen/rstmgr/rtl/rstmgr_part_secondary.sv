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
  input clk_aon_i,
  input clk_io_div4_i,
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
  assign resets_generated.rst_por_aon_n[DomainMainSel] = rst_por_aon_n[DomainMainSel];
  assign rst_en_generated.por_aon[DomainMainSel] = rst_en_por_aon[DomainMainSel];
  assign resets_generated.rst_por_aon_n[DomainAonSel] = rst_por_aon_n[DomainAonSel];
  assign rst_en_generated.por_aon[DomainAonSel] = rst_en_por_aon[DomainAonSel];

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
  logic [4:0] cnsty_chk_errs;
  logic [4:0] fsm_errs;

  ////////////////////////////////////////////////////
  // Leaf resets of the secondary partition         //
  // The primary partition generates every other    //
  // leaf reset.                                    //
  ////////////////////////////////////////////////////
  // Generating resets for por_io_div4
  // Power Domains: ['Aon'], hosted in this partition: ['Aon']
  // Shadowed: False
  rstmgr_leaf_rst #(
    .SecCheck(SecCheck),
    .SecMaxSyncDelay(SecMaxSyncDelay),
    .SwRstReq(1'b0)
  ) u_daon_por_io_div4 (
    .clk_i,
    .rst_ni,
    .leaf_clk_i(clk_io_div4_i),
    .parent_rst_ni(rst_por_aon_n[DomainAonSel]),
    .sw_rst_req_ni(1'b1),
    .scan_rst_ni(scan_rst_n),
    .scanmode_i(scanmode),
    .rst_en_o(rst_en_generated.por_io_div4),
    .leaf_rst_o(resets_generated.rst_por_io_div4_n),
    .err_o(cnsty_chk_errs[0]),
    .fsm_err_o(fsm_errs[0])
  );
  // The assertion uses _ERR rather than _ALERT on purpose, as this partition has no alert. The FSM
  // error leaves this partition through intraip_s2p_o.fsm_err, and the primary partition turns it
  // into its fatal alert.
  if (SecCheck) begin : gen_daon_por_io_div4_assert
  `ASSERT_PRIM_FSM_ERROR_TRIGGER_ERR(
    DAonPorIoDiv4FsmCheck_A,
    u_daon_por_io_div4.gen_rst_chk.u_rst_chk.u_state_regs,
    intraip_s2p_o.fsm_err)
  end
  // Generating resets for lc_aon
  // Power Domains: ['Main', 'Aon'], hosted in this partition: ['Aon']
  // Shadowed: False
  rstmgr_leaf_rst #(
    .SecCheck(SecCheck),
    .SecMaxSyncDelay(SecMaxSyncDelay),
    .SwRstReq(1'b0)
  ) u_daon_lc_aon (
    .clk_i,
    .rst_ni,
    .leaf_clk_i(clk_aon_i),
    .parent_rst_ni(rst_lc_src_n[DomainAonSel]),
    .sw_rst_req_ni(1'b1),
    .scan_rst_ni(scan_rst_n),
    .scanmode_i(scanmode),
    .rst_en_o(rst_en_generated.lc_aon),
    .leaf_rst_o(resets_generated.rst_lc_aon_n),
    .err_o(cnsty_chk_errs[1]),
    .fsm_err_o(fsm_errs[1])
  );
  // The assertion uses _ERR rather than _ALERT on purpose, as this partition has no alert. The FSM
  // error leaves this partition through intraip_s2p_o.fsm_err, and the primary partition turns it
  // into its fatal alert.
  if (SecCheck) begin : gen_daon_lc_aon_assert
  `ASSERT_PRIM_FSM_ERROR_TRIGGER_ERR(
    DAonLcAonFsmCheck_A,
    u_daon_lc_aon.gen_rst_chk.u_rst_chk.u_state_regs,
    intraip_s2p_o.fsm_err)
  end
  // Generating resets for lc_io_div4
  // Power Domains: ['Main', 'Aon'], hosted in this partition: ['Aon']
  // Shadowed: True
  rstmgr_leaf_rst #(
    .SecCheck(0),
    .SecMaxSyncDelay(SecMaxSyncDelay),
    .SwRstReq(1'b0)
  ) u_daon_lc_io_div4 (
    .clk_i,
    .rst_ni,
    .leaf_clk_i(clk_io_div4_i),
    .parent_rst_ni(rst_lc_src_n[DomainAonSel]),
    .sw_rst_req_ni(1'b1),
    .scan_rst_ni(scan_rst_n),
    .scanmode_i(scanmode),
    .rst_en_o(rst_en_generated.lc_io_div4),
    .leaf_rst_o(resets_generated.rst_lc_io_div4_n),
    .err_o(cnsty_chk_errs[2]),
    .fsm_err_o(fsm_errs[2])
  );
  rstmgr_leaf_rst #(
    .SecCheck(0),
    .SecMaxSyncDelay(SecMaxSyncDelay),
    .SwRstReq(1'b0)
  ) u_daon_lc_io_div4_shadowed (
    .clk_i,
    .rst_ni,
    .leaf_clk_i(clk_io_div4_i),
    .parent_rst_ni(rst_lc_src_n[DomainAonSel]),
    .sw_rst_req_ni(1'b1),
    .scan_rst_ni(scan_rst_n),
    .scanmode_i(scanmode),
    .rst_en_o(rst_en_generated.lc_io_div4_shadowed),
    .leaf_rst_o(resets_generated.rst_lc_io_div4_shadowed_n),
    .err_o(cnsty_chk_errs[3]),
    .fsm_err_o(fsm_errs[3])
  );
  // Generating resets for sys_io_div4
  // Power Domains: ['Aon'], hosted in this partition: ['Aon']
  // Shadowed: False
  rstmgr_leaf_rst #(
    .SecCheck(SecCheck),
    .SecMaxSyncDelay(SecMaxSyncDelay),
    .SwRstReq(1'b0)
  ) u_daon_sys_io_div4 (
    .clk_i,
    .rst_ni,
    .leaf_clk_i(clk_io_div4_i),
    .parent_rst_ni(rst_sys_src_n[DomainAonSel]),
    .sw_rst_req_ni(1'b1),
    .scan_rst_ni(scan_rst_n),
    .scanmode_i(scanmode),
    .rst_en_o(rst_en_generated.sys_io_div4),
    .leaf_rst_o(resets_generated.rst_sys_io_div4_n),
    .err_o(cnsty_chk_errs[4]),
    .fsm_err_o(fsm_errs[4])
  );
  // The assertion uses _ERR rather than _ALERT on purpose, as this partition has no alert. The FSM
  // error leaves this partition through intraip_s2p_o.fsm_err, and the primary partition turns it
  // into its fatal alert.
  if (SecCheck) begin : gen_daon_sys_io_div4_assert
  `ASSERT_PRIM_FSM_ERROR_TRIGGER_ERR(
    DAonSysIoDiv4FsmCheck_A,
    u_daon_sys_io_div4.gen_rst_chk.u_rst_chk.u_state_regs,
    intraip_s2p_o.fsm_err)
  end

  ////////////////////////////////////////////////////
  // Signalling to the primary partition            //
  ////////////////////////////////////////////////////
  assign intraip_s2p_o.rst_por_aon_n_aon = rst_por_aon_n[DomainAonSel];
  assign intraip_s2p_o.rst_lc_src_n_main = rst_lc_src_n[DomainMainSel];
  assign intraip_s2p_o.rst_lc_src_n_aon = rst_lc_src_n[DomainAonSel];
  assign intraip_s2p_o.rst_sys_src_n_main = rst_sys_src_n[DomainMainSel];
  assign intraip_s2p_o.pwr                  = pwr_i;
  // The consistency and FSM errors of the leaves that this partition hosts. Without leaves,
  // there is no error.
  assign intraip_s2p_o.cnsty_chk_err          = |cnsty_chk_errs;
  assign intraip_s2p_o.fsm_err                = |fsm_errs;

  ////////////////////////////////////////////////////
  // Assertions                                     //
  ////////////////////////////////////////////////////
  `ASSERT_KNOWN(PwrKnownO_A,         pwr_o         )
  ////////////////////////////////////////////////////
  // Routing. This partition outputs the resets that its power domain uses.
  ////////////////////////////////////////////////////
  assign resets_secondary_o.rst_por_aon_n[DomainMainSel] =
      resets_generated.rst_por_aon_n[DomainMainSel];
  assign resets_secondary_o.rst_por_aon_n[DomainAonSel] =
      resets_generated.rst_por_aon_n[DomainAonSel];
  assign resets_secondary_o.rst_por_io_div4_n = resets_generated.rst_por_io_div4_n;
  assign intraip_s2p_o.rst_por_io_div4_n_aon = resets_generated.rst_por_io_div4_n;
  assign resets_secondary_o.rst_lc_aon_n = resets_generated.rst_lc_aon_n;
  assign intraip_s2p_o.rst_lc_aon_n_aon = resets_generated.rst_lc_aon_n;
  assign resets_secondary_o.rst_lc_io_div4_n[DomainMainSel] = intraip_p2s_i.rst_lc_io_div4_n_main;
  assign resets_secondary_o.rst_lc_io_div4_n[DomainAonSel] = resets_generated.rst_lc_io_div4_n;
  assign intraip_s2p_o.rst_lc_io_div4_n_aon = resets_generated.rst_lc_io_div4_n;
  assign resets_secondary_o.rst_lc_io_div4_shadowed_n[DomainMainSel] =
      intraip_p2s_i.rst_lc_io_div4_shadowed_n_main;
  assign resets_secondary_o.rst_lc_io_div4_shadowed_n[DomainAonSel] =
      resets_generated.rst_lc_io_div4_shadowed_n;
  assign intraip_s2p_o.rst_lc_io_div4_shadowed_n_aon = resets_generated.rst_lc_io_div4_shadowed_n;
  assign resets_secondary_o.rst_sys_io_div4_n = resets_generated.rst_sys_io_div4_n;

  // The reset asserted indications that this partition generates go to the primary partition,
  // which outputs them.
  assign intraip_s2p_o.rst_en_por_aon_main = rst_en_generated.por_aon[DomainMainSel];
  assign intraip_s2p_o.rst_en_por_aon_aon = rst_en_generated.por_aon[DomainAonSel];
  assign intraip_s2p_o.rst_en_por_io_div4_aon = rst_en_generated.por_io_div4;
  assign intraip_s2p_o.rst_en_lc_aon_aon = rst_en_generated.lc_aon;
  assign intraip_s2p_o.rst_en_lc_io_div4_aon = rst_en_generated.lc_io_div4;
  assign intraip_s2p_o.rst_en_lc_io_div4_shadowed_aon = rst_en_generated.lc_io_div4_shadowed;
  assign intraip_s2p_o.rst_en_sys_io_div4_aon = rst_en_generated.sys_io_div4;

  `ASSERT_KNOWN(ResetsKnownO_A,      resets_secondary_o      )
  `ASSERT_KNOWN(IntraipKnownO_A,   intraip_s2p_o)
endmodule // rstmgr_part_secondary
