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
  input logic clk_aon_i,
  input logic clk_io_div4_i,
  input logic clk_main_i,
  input logic clk_io_i,
  input logic clk_usb_i,
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

  `ASSERT(DAonRstPorUsbEnTracksRstPorUsbActive_A,
          $fell(resets_generated.rst_por_usb_n) |-> ##[0:DELAY]
          rst_en_generated.por_usb == prim_mubi_pkg::MuBi4True,
          clk_usb_i,
          !rst_por_ni)

  `ASSERT(DAonRstPorUsbEnTracksRstPorUsbInactive_A,
          $rose(resets_generated.rst_por_usb_n) |-> ##DELAY
          !resets_generated.rst_por_usb_n ||
          rst_en_generated.por_usb == prim_mubi_pkg::MuBi4False,
          clk_usb_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcShadowedEnTracksRstLcShadowedActive_A,
          $fell(resets_generated.rst_lc_shadowed_n) |-> ##[0:DELAY]
          rst_en_generated.lc_shadowed == prim_mubi_pkg::MuBi4True,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcShadowedEnTracksRstLcShadowedInactive_A,
          $rose(resets_generated.rst_lc_shadowed_n) |-> ##DELAY
          !resets_generated.rst_lc_shadowed_n ||
          rst_en_generated.lc_shadowed == prim_mubi_pkg::MuBi4False,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcIoDiv4EnTracksRstLcIoDiv4Active_A,
          $fell(resets_generated.rst_lc_io_div4_n) |-> ##[0:DELAY]
          rst_en_generated.lc_io_div4 == prim_mubi_pkg::MuBi4True,
          clk_io_div4_i,
          !rst_por_ni)

  `ASSERT(DMainRstLcIoDiv4EnTracksRstLcIoDiv4Inactive_A,
          $rose(resets_generated.rst_lc_io_div4_n) |-> ##DELAY
          !resets_generated.rst_lc_io_div4_n ||
          rst_en_generated.lc_io_div4 == prim_mubi_pkg::MuBi4False,
          clk_io_div4_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysShadowedEnTracksRstSysShadowedActive_A,
          $fell(resets_generated.rst_sys_shadowed_n) |-> ##[0:DELAY]
          rst_en_generated.sys_shadowed == prim_mubi_pkg::MuBi4True,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysShadowedEnTracksRstSysShadowedInactive_A,
          $rose(resets_generated.rst_sys_shadowed_n) |-> ##DELAY
          !resets_generated.rst_sys_shadowed_n ||
          rst_en_generated.sys_shadowed == prim_mubi_pkg::MuBi4False,
          clk_main_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysIoDiv4EnTracksRstSysIoDiv4Active_A,
          $fell(resets_generated.rst_sys_io_div4_n) |-> ##[0:DELAY]
          rst_en_generated.sys_io_div4 == prim_mubi_pkg::MuBi4True,
          clk_io_div4_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysIoDiv4EnTracksRstSysIoDiv4Inactive_A,
          $rose(resets_generated.rst_sys_io_div4_n) |-> ##DELAY
          !resets_generated.rst_sys_io_div4_n ||
          rst_en_generated.sys_io_div4 == prim_mubi_pkg::MuBi4False,
          clk_io_div4_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysAonEnTracksRstSysAonActive_A,
          $fell(resets_generated.rst_sys_aon_n) |-> ##[0:DELAY]
          rst_en_generated.sys_aon == prim_mubi_pkg::MuBi4True,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DMainRstSysAonEnTracksRstSysAonInactive_A,
          $rose(resets_generated.rst_sys_aon_n) |-> ##DELAY
          !resets_generated.rst_sys_aon_n ||
          rst_en_generated.sys_aon == prim_mubi_pkg::MuBi4False,
          clk_aon_i,
          !rst_por_ni)

  `ASSERT(DMainRstSpiDeviceEnTracksRstSpiDeviceActive_A,
          $fell(resets_generated.rst_spi_device_n) |-> ##[0:DELAY]
          rst_en_generated.spi_device == prim_mubi_pkg::MuBi4True,
          clk_io_div4_i,
          !rst_por_ni)

  `ASSERT(DMainRstSpiDeviceEnTracksRstSpiDeviceInactive_A,
          $rose(resets_generated.rst_spi_device_n) |-> ##DELAY
          !resets_generated.rst_spi_device_n ||
          rst_en_generated.spi_device == prim_mubi_pkg::MuBi4False,
          clk_io_div4_i,
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

  `ASSERT(DMainRstUsbEnTracksRstUsbActive_A,
          $fell(resets_generated.rst_usb_n) |-> ##[0:DELAY]
          rst_en_generated.usb == prim_mubi_pkg::MuBi4True,
          clk_usb_i,
          !rst_por_ni)

  `ASSERT(DMainRstUsbEnTracksRstUsbInactive_A,
          $rose(resets_generated.rst_usb_n) |-> ##DELAY
          !resets_generated.rst_usb_n ||
          rst_en_generated.usb == prim_mubi_pkg::MuBi4False,
          clk_usb_i,
          !rst_por_ni)

endinterface
