// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The indication checks of the single power-domain reset manager, for the resets that the primary
// partition generates. rstmgr_bind binds this interface to rstmgr_part_primary.
// rstmgr_rst_en_track_secondary_sva_if has the checks of the resets that the secondary partition
// generates.

// This checks that the outgoing resets and the corresponding reset enable going to alert handler
// are shifted by a single clock cycle.
interface rstmgr_rst_en_track_primary_sva_if (
  input logic clk_io_i,
  input logic clk_main_i,
  input logic rst_por_ni,
  input rstmgr_pkg::rstmgr_generated_primary_t resets_generated,
  input rstmgr_pkg::rstmgr_rst_en_generated_primary_t rst_en_generated
);
  localparam int DELAY = 1;

  `ASSERT(DAonRstPorEnTracksRstPorActive_A,
          $fell(resets_generated.rst_por_n) |-> ##[0:DELAY]
          rst_en_generated.por == prim_mubi_pkg::MuBi4True,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DAonRstPorEnTracksRstPorInactive_A,
          $rose(resets_generated.rst_por_n) |-> ##DELAY
          !resets_generated.rst_por_n ||
          rst_en_generated.por == prim_mubi_pkg::MuBi4False,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcShadowedEnTracksRstLcShadowedActive_A,
          $fell(resets_generated.rst_lc_shadowed_n[rstmgr_pkg::DomainMainSel]) |-> ##[0:DELAY]
          rst_en_generated.lc_shadowed[rstmgr_pkg::DomainMainSel] == prim_mubi_pkg::MuBi4True,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcShadowedEnTracksRstLcShadowedInactive_A,
          $rose(resets_generated.rst_lc_shadowed_n[rstmgr_pkg::DomainMainSel]) |-> ##DELAY
          !resets_generated.rst_lc_shadowed_n[rstmgr_pkg::DomainMainSel] ||
          rst_en_generated.lc_shadowed[rstmgr_pkg::DomainMainSel] == prim_mubi_pkg::MuBi4False,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DAonRstLcShadowedEnTracksRstLcShadowedActive_A,
          $fell(resets_generated.rst_lc_shadowed_n[rstmgr_pkg::DomainAonSel]) |-> ##[0:DELAY]
          rst_en_generated.lc_shadowed[rstmgr_pkg::DomainAonSel] == prim_mubi_pkg::MuBi4True,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DAonRstLcShadowedEnTracksRstLcShadowedInactive_A,
          $rose(resets_generated.rst_lc_shadowed_n[rstmgr_pkg::DomainAonSel]) |-> ##DELAY
          !resets_generated.rst_lc_shadowed_n[rstmgr_pkg::DomainAonSel] ||
          rst_en_generated.lc_shadowed[rstmgr_pkg::DomainAonSel] == prim_mubi_pkg::MuBi4False,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcIoShadowedEnTracksRstLcIoShadowedActive_A,
          $fell(resets_generated.rst_lc_io_shadowed_n) |-> ##[0:DELAY]
          rst_en_generated.lc_io_shadowed == prim_mubi_pkg::MuBi4True,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcIoShadowedEnTracksRstLcIoShadowedInactive_A,
          $rose(resets_generated.rst_lc_io_shadowed_n) |-> ##DELAY
          !resets_generated.rst_lc_io_shadowed_n ||
          rst_en_generated.lc_io_shadowed == prim_mubi_pkg::MuBi4False,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysEnTracksRstSysActive_A,
          $fell(resets_generated.rst_sys_n) |-> ##[0:DELAY]
          rst_en_generated.sys == prim_mubi_pkg::MuBi4True,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysEnTracksRstSysInactive_A,
          $rose(resets_generated.rst_sys_n) |-> ##DELAY
          !resets_generated.rst_sys_n ||
          rst_en_generated.sys == prim_mubi_pkg::MuBi4False,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstSpiDeviceEnTracksRstSpiDeviceActive_A,
          $fell(resets_generated.rst_spi_device_n) |-> ##[0:DELAY]
          rst_en_generated.spi_device == prim_mubi_pkg::MuBi4True,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstSpiDeviceEnTracksRstSpiDeviceInactive_A,
          $rose(resets_generated.rst_spi_device_n) |-> ##DELAY
          !resets_generated.rst_spi_device_n ||
          rst_en_generated.spi_device == prim_mubi_pkg::MuBi4False,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstSpiHost0EnTracksRstSpiHost0Active_A,
          $fell(resets_generated.rst_spi_host0_n) |-> ##[0:DELAY]
          rst_en_generated.spi_host0 == prim_mubi_pkg::MuBi4True,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstSpiHost0EnTracksRstSpiHost0Inactive_A,
          $rose(resets_generated.rst_spi_host0_n) |-> ##DELAY
          !resets_generated.rst_spi_host0_n ||
          rst_en_generated.spi_host0 == prim_mubi_pkg::MuBi4False,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstI2c0EnTracksRstI2c0Active_A,
          $fell(resets_generated.rst_i2c0_n) |-> ##[0:DELAY]
          rst_en_generated.i2c0 == prim_mubi_pkg::MuBi4True,
          clk_io_i,
          !rst_por_ni)

  `ASSERT(DMainRstI2c0EnTracksRstI2c0Inactive_A,
          $rose(resets_generated.rst_i2c0_n) |-> ##DELAY
          !resets_generated.rst_i2c0_n ||
          rst_en_generated.i2c0 == prim_mubi_pkg::MuBi4False,
          clk_io_i,
          !rst_por_ni)

endinterface
