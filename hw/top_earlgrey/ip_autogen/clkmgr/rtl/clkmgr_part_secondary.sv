// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Secondary partition of the split clock manager.
//
// The secondary partition hosts only the always-on clocks, with their root buffers and the
// feed-through buffers of the typed clocks that come from them. These clocks are never gated. So
// this partition has no registers and no state, and the always-on clocks keep running while the
// power domain of the primary partition is down.
//
// The always-on source clocks and their resets enter the block here.

`include "prim_assert.sv"

module clkmgr_part_secondary
  import clkmgr_pkg::*;
  import prim_mubi_pkg::mubi4_t;
(
  // Source clocks of this partition, and their resets
  input clk_aon_i,
  input rst_aon_ni,

  // Power manager interface. The power manager is in the power domain of this partition.
  input pwrmgr_pkg::pwr_clk_req_t pwr_i,
  output pwrmgr_pkg::pwr_clk_rsp_t pwr_o,


  // clock output interface
  output clkmgr_out_secondary_t clocks_secondary_o,

  // inter-partition signalling
  output intraip_s2p_t intraip_s2p_o,
  input intraip_p2s_t intraip_p2s_i
);

  import prim_mubi_pkg::MuBi4False;

  // The primary partition uses the power manager's requests and answers them.
  assign intraip_s2p_o.main_ip_clk_en = pwr_i.main_ip_clk_en;
  assign pwr_o.main_status = intraip_p2s_i.main_status;
  assign intraip_s2p_o.io_ip_clk_en = pwr_i.io_ip_clk_en;
  assign pwr_o.io_status = intraip_p2s_i.io_status;
  assign intraip_s2p_o.usb_ip_clk_en = pwr_i.usb_ip_clk_en;
  assign pwr_o.usb_status = intraip_p2s_i.usb_status;

  // Hookup point for OCC's on root clocks.
  logic clk_aon;
  prim_clock_buf #(
    .NoFpgaBuf(1'b1)
  ) u_clk_aon_buf (
    .clk_i(clk_aon_i),
    .clk_o(clk_aon)
  );

  // The primary partition takes the buffered clock of this source from here. Each source clock
  // comes with its reset, as the clocking of the IP declares them in pairs. The assertions below
  // use the reset of the first source, and no other logic here uses these resets. The primary
  // partition has its own ports for them, for the clock measurement.
  assign intraip_s2p_o.clk_aon = clk_aon;
  logic unused_rst_aon_ni;
  assign unused_rst_aon_ni = rst_aon_ni;

  ////////////////////////////////////////////////////
  // Feed-through clocks sourced from the always-on clocks
  ////////////////////////////////////////////////////
  prim_clock_buf u_clk_aon_powerup_buf (
    .clk_i(clk_aon),
    .clk_o(clocks_secondary_o.clk_aon_powerup)
  );

  // clock gated indication for alert handler: these clocks are never gated.
  prim_clock_buf u_clk_aon_secure_buf (
    .clk_i(clk_aon),
    .clk_o(clocks_secondary_o.clk_aon_secure)
  );

  // clock gated indication for alert handler: these clocks are never gated.
  // The primary partition outputs the clock gating indication. A feed-through clock is never gated,
  // so the indication is MuBi4False.
  assign intraip_s2p_o.cg_en_aon_secure = MuBi4False;
  prim_clock_buf u_clk_aon_peri_buf (
    .clk_i(clk_aon),
    .clk_o(clocks_secondary_o.clk_aon_peri)
  );

  // clock gated indication for alert handler: these clocks are never gated.
  prim_clock_buf u_clk_aon_timers_buf (
    .clk_i(clk_aon),
    .clk_o(clocks_secondary_o.clk_aon_timers)
  );

  // clock gated indication for alert handler: these clocks are never gated.
  // The primary partition outputs the clock gating indication. A feed-through clock is never gated,
  // so the indication is MuBi4False.
  assign intraip_s2p_o.cg_en_aon_timers = MuBi4False;

  ////////////////////////////////////////////////////
  // Clocks the primary partition generates for this power domain
  ////////////////////////////////////////////////////
  prim_clock_buf u_clk_io_div4_powerup_buf (
    .clk_i(intraip_p2s_i.clk_io_div4),
    .clk_o(clocks_secondary_o.clk_io_div4_powerup)
  );
  assign clocks_secondary_o.clk_io_div4_infra = intraip_p2s_i.clk_io_div4_root;
  assign clocks_secondary_o.clk_io_div4_secure = intraip_p2s_i.clk_io_div4_root;
  assign clocks_secondary_o.clk_io_div4_timers = intraip_p2s_i.clk_io_div4_root;
  assign clocks_secondary_o.clk_io_div4_peri = intraip_p2s_i.clk_io_div4_peri;

  ////////////////////////////////////////////////////
  // Assertions
  ////////////////////////////////////////////////////
  // The secondary partition has no clk_i or rst_ni. Its assertions use the clock and reset of its
  // first source.
  `ASSERT_KNOWN(ClocksKownO_A, clocks_secondary_o, clk_aon_i, !rst_aon_ni)
  `ASSERT_KNOWN(PwrMgrKnownO_A, pwr_o, clk_aon_i, !rst_aon_ni)
  `ASSERT_KNOWN(IntraipKnownO_A, intraip_s2p_o, clk_aon_i, !rst_aon_ni)
endmodule // clkmgr_part_secondary
