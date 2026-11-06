// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//

package rstmgr_pkg;

  // Power domain parameters
  parameter int PowerDomains = 2;
  parameter int DomainAonSel = 0;
  parameter int DomainMainSel = 1;

  // Number of non-always-on domains
  parameter int OffDomains = PowerDomains-1;

  // positions of software controllable reset bits
  parameter int SPI_DEVICE = 0;
  parameter int SPI_HOST0 = 1;
  parameter int I2C0 = 2;

  // Resets generated and broadcast. Each partition outputs the resets that its power domain uses.
  // A reset that a partition outputs for every power domain is an array over the domains. A reset
  // that it outputs for a single power domain is a single bit.
  // SEC_CM: LEAF.RST.SHADOW
  typedef struct packed {
    logic [PowerDomains-1:0] rst_por_aon_n;
    logic rst_por_io_n;
    logic rst_lc_aon_n;
    logic rst_lc_io_shadowed_n;
    logic rst_lc_io_n;
  } rstmgr_out_secondary_t;

  // SEC_CM: LEAF.RST.SHADOW
  typedef struct packed {
    logic rst_por_n;
    logic [PowerDomains-1:0] rst_lc_shadowed_n;
    logic [PowerDomains-1:0] rst_lc_n;
    logic rst_lc_io_shadowed_n;
    logic rst_lc_io_n;
    logic rst_sys_n;
    logic rst_spi_device_n;
    logic rst_spi_host0_n;
    logic rst_i2c0_n;
  } rstmgr_out_primary_t;

  // Each struct below holds all the resets that a partition generates, before the routing to the
  // partitions.
  typedef struct packed {
    logic [PowerDomains-1:0] rst_por_aon_n;
    logic rst_por_io_n;
    logic rst_lc_aon_n;
    logic rst_lc_io_shadowed_n;
    logic rst_lc_io_n;
  } rstmgr_generated_secondary_t;

  typedef struct packed {
    logic rst_por_n;
    logic [PowerDomains-1:0] rst_lc_shadowed_n;
    logic [PowerDomains-1:0] rst_lc_n;
    logic rst_lc_io_shadowed_n;
    logic rst_lc_io_n;
    logic rst_sys_n;
    logic rst_spi_device_n;
    logic rst_spi_host0_n;
    logic rst_i2c0_n;
  } rstmgr_generated_primary_t;

  // Reset asserted indications for the alert handlers. The primary partition outputs all of them.
  // The secondary partition's indications cross to it in intraip_s2p.
  typedef struct packed {
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] por_aon;
    prim_mubi_pkg::mubi4_t por;
    prim_mubi_pkg::mubi4_t por_io;
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] lc_shadowed;
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] lc;
    prim_mubi_pkg::mubi4_t lc_aon;
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] lc_io_shadowed;
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] lc_io;
    prim_mubi_pkg::mubi4_t sys;
    prim_mubi_pkg::mubi4_t spi_device;
    prim_mubi_pkg::mubi4_t spi_host0;
    prim_mubi_pkg::mubi4_t i2c0;
  } rstmgr_rst_en_primary_t;

  // Each struct below holds all the reset asserted indications that a partition generates, before
  // the routing.
  typedef struct packed {
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] por_aon;
    prim_mubi_pkg::mubi4_t por_io;
    prim_mubi_pkg::mubi4_t lc_aon;
    prim_mubi_pkg::mubi4_t lc_io_shadowed;
    prim_mubi_pkg::mubi4_t lc_io;
  } rstmgr_rst_en_generated_secondary_t;

  typedef struct packed {
    prim_mubi_pkg::mubi4_t por;
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] lc_shadowed;
    prim_mubi_pkg::mubi4_t [PowerDomains-1:0] lc;
    prim_mubi_pkg::mubi4_t lc_io_shadowed;
    prim_mubi_pkg::mubi4_t lc_io;
    prim_mubi_pkg::mubi4_t sys;
    prim_mubi_pkg::mubi4_t spi_device;
    prim_mubi_pkg::mubi4_t spi_host0;
    prim_mubi_pkg::mubi4_t i2c0;
  } rstmgr_rst_en_generated_primary_t;

  parameter int NumOutputRst = 12 * PowerDomains;

  // Signalling between the two partitions of the split reset manager.
  // Secondary (reset roots, always-on side) to primary
  typedef struct packed {
    // The reset roots, per power domain, that the primary partition's leaf resets have as parents.
    logic rst_por_aon_n_aon;
    logic rst_lc_src_n_main;
    logic rst_lc_src_n_aon;
    logic rst_sys_src_n_main;
    // The power manager's reset request, forwarded for the RESET_INFO logic.
    pwrmgr_pkg::pwr_rst_req_t pwr;
    // The aggregated errors of the leaf resets that the secondary partition hosts.
    logic cnsty_chk_err;
    logic fsm_err;
    // The resets that the secondary partition generates and the primary partition's power domain
    // uses.
    // The reset asserted indications that the secondary partition generates. The primary partition
    // outputs them.
    prim_mubi_pkg::mubi4_t rst_en_por_aon_main;
    prim_mubi_pkg::mubi4_t rst_en_por_aon_aon;
    prim_mubi_pkg::mubi4_t rst_en_por_io_aon;
    prim_mubi_pkg::mubi4_t rst_en_lc_aon_aon;
    prim_mubi_pkg::mubi4_t rst_en_lc_io_aon;
    prim_mubi_pkg::mubi4_t rst_en_lc_io_shadowed_aon;
  } intraip_s2p_t;

  // Primary to secondary
  typedef struct packed {
    // Nothing flows to the secondary partition in this configuration. The reserved field keeps the
    // struct from being empty.
    logic reserved;
  } intraip_p2s_t;

  // cpu reset requests and status
  typedef struct packed {
    logic ndmreset_req;
  } rstmgr_cpu_t;

  // exported resets

  // default value for rstmgr_ast_rsp_t (for dangling ports)
  parameter rstmgr_cpu_t RSTMGR_CPU_DEFAULT = '{
    ndmreset_req: '0
  };

  // Enumeration for pwrmgr hw reset inputs
  import rstmgr_reg_pkg::NumTotalResets;
  localparam int ResetWidths = $clog2(NumTotalResets);
  typedef enum logic [ResetWidths-1:0] {
    ReqPeriResetIdx[0:1],
    ReqMainPwrResetIdx,
    ReqEscResetIdx,
    ReqNdmResetIdx
  } reset_req_idx_e;

  // Enumeration for reset info bit idx
  typedef enum logic [ResetWidths-1:0] {
    InfoPorIdx,
    InfoLowPowerExitIdx,
    InfoSwResetIdx,
    InfoPeriResetIdx[0:1],
    InfoMainPwrResetIdx,
    InfoEscResetIdx,
    InfoNdmResetIdx
  } reset_info_idx_e;


endpackage // rstmgr_pkg
