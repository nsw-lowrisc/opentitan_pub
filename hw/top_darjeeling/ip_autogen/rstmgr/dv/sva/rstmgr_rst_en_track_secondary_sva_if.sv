// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The indication checks of the single power-domain reset manager, for the resets that the secondary
// partition generates. rstmgr_bind binds this interface to rstmgr_part_secondary.
// rstmgr_rst_en_track_primary_sva_if has the checks of the resets that the primary partition
// generates.

// This checks that the outgoing resets and the corresponding reset enable going to alert handler
// are shifted by a single clock cycle.
interface rstmgr_rst_en_track_secondary_sva_if (
  input logic clk_aon_i,
  input logic clk_io_i,
  input logic rst_por_ni,
  input rstmgr_pkg::rstmgr_generated_secondary_t resets_generated,
  input rstmgr_pkg::rstmgr_rst_en_generated_secondary_t rst_en_generated
);
  localparam int DELAY = 1;

  `ASSERT(DMainRstPorAonEnTracksRstPorAonActive_A,
          $fell(resets_generated.rst_por_aon_n[rstmgr_pkg::DomainMainSel]) |-> ##[0:DELAY]
          rst_en_generated.por_aon[rstmgr_pkg::DomainMainSel] == prim_mubi_pkg::MuBi4True,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DMainRstPorAonEnTracksRstPorAonInactive_A,
          $rose(resets_generated.rst_por_aon_n[rstmgr_pkg::DomainMainSel]) |-> ##DELAY
          !resets_generated.rst_por_aon_n[rstmgr_pkg::DomainMainSel] ||
          rst_en_generated.por_aon[rstmgr_pkg::DomainMainSel] == prim_mubi_pkg::MuBi4False,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DAonRstPorAonEnTracksRstPorAonActive_A,
          $fell(resets_generated.rst_por_aon_n[rstmgr_pkg::DomainAonSel]) |-> ##[0:DELAY]
          rst_en_generated.por_aon[rstmgr_pkg::DomainAonSel] == prim_mubi_pkg::MuBi4True,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DAonRstPorAonEnTracksRstPorAonInactive_A,
          $rose(resets_generated.rst_por_aon_n[rstmgr_pkg::DomainAonSel]) |-> ##DELAY
          !resets_generated.rst_por_aon_n[rstmgr_pkg::DomainAonSel] ||
          rst_en_generated.por_aon[rstmgr_pkg::DomainAonSel] == prim_mubi_pkg::MuBi4False,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DAonRstPorIoEnTracksRstPorIoActive_A,
          $fell(resets_generated.rst_por_io_n) |-> ##[0:DELAY]
          rst_en_generated.por_io == prim_mubi_pkg::MuBi4True,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DAonRstPorIoEnTracksRstPorIoInactive_A,
          $rose(resets_generated.rst_por_io_n) |-> ##DELAY
          !resets_generated.rst_por_io_n ||
          rst_en_generated.por_io == prim_mubi_pkg::MuBi4False,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DAonRstLcAonEnTracksRstLcAonActive_A,
          $fell(resets_generated.rst_lc_aon_n) |-> ##[0:DELAY]
          rst_en_generated.lc_aon == prim_mubi_pkg::MuBi4True,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DAonRstLcAonEnTracksRstLcAonInactive_A,
          $rose(resets_generated.rst_lc_aon_n) |-> ##DELAY
          !resets_generated.rst_lc_aon_n ||
          rst_en_generated.lc_aon == prim_mubi_pkg::MuBi4False,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DAonRstLcIoShadowedEnTracksRstLcIoShadowedActive_A,
          $fell(resets_generated.rst_lc_io_shadowed_n) |-> ##[0:DELAY]
          rst_en_generated.lc_io_shadowed == prim_mubi_pkg::MuBi4True,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DAonRstLcIoShadowedEnTracksRstLcIoShadowedInactive_A,
          $rose(resets_generated.rst_lc_io_shadowed_n) |-> ##DELAY
          !resets_generated.rst_lc_io_shadowed_n ||
          rst_en_generated.lc_io_shadowed == prim_mubi_pkg::MuBi4False,
          clk_io_i,
          !rst_por_ni)

endinterface
