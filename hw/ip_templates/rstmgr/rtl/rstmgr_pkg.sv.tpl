// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
<%
  peri_reqs = reqs.get("peripheral", [])
  int_reqs = reqs.get("int", [])
  debug_reqs = reqs.get("debug", [])
  from ipgen.manager_split import (rstmgr_clocks, rstmgr_hosted_domains, rstmgr_is_array,
                                   rstmgr_out_domains, rstmgr_routed_rsts, rstmgr_rst_en_routed,
                                   rstmgr_routed_roots)
  # The resets that a partition generates cross to the other partition once, as single bits, if
  # the other partition's power domain uses them.
  def routed_rsts(to_part):
    return rstmgr_routed_rsts(output_rsts, to_part)
  split_clks = rstmgr_clocks(clk_freqs, leaf_rsts, rst_ni)
  aon_clks = split_clks.aon
  n_rst = sum(2 if r['shadowed'] else 1 for r in output_rsts)
%>\

package rstmgr_pkg;

  // Power domain parameters
  parameter int PowerDomains = ${len(power_domains)};
  % for power_domain in power_domains:
  parameter int Domain${power_domain}Sel = ${loop.index};
  % endfor

  // Number of non-always-on domains
  parameter int OffDomains = PowerDomains-1;

  // positions of software controllable reset bits
% for device in sw_rsts.keys():
  parameter int ${device.upper()} = ${loop.index};
% endfor

  // Resets generated and broadcast. Each partition outputs the resets that its power domain uses.
  // A reset that a partition outputs for every power domain is an array over the domains. A reset
  // that it outputs for a single power domain is a single bit.
% for part in ('secondary', 'primary'):
  // SEC_CM: LEAF.RST.SHADOW
  typedef struct packed {
  % for rst in output_rsts:
<% outs = rstmgr_out_domains(rst, part)
arr = '[PowerDomains-1:0] ' if outs and rstmgr_is_array(outs, power_domains) else '' %>\
    % if outs:
      % if rst['shadowed']:
    logic ${arr}rst_${rst['name']}_shadowed_n;
      % endif
    logic ${arr}rst_${rst['name']}_n;
    % endif
  % endfor
  } rstmgr_out_${part}_t;

% endfor
  // Each struct below holds all the resets that a partition generates, before the routing to the
  // partitions.
% for part in ('secondary', 'primary'):
  typedef struct packed {
  % for rst in output_rsts:
<% hosted = rstmgr_hosted_domains(rst, part)
arr = '[PowerDomains-1:0] ' if hosted and rstmgr_is_array(hosted, power_domains) else '' %>\
    % if hosted:
      % if rst['shadowed']:
    logic ${arr}rst_${rst['name']}_shadowed_n;
      % endif
    logic ${arr}rst_${rst['name']}_n;
    % endif
  % endfor
  } rstmgr_generated_${part}_t;

% endfor
  // Reset asserted indications for the alert handlers. The primary partition outputs all of them.
  // The secondary partition's indications cross to it in intraip_s2p.
  typedef struct packed {
% for rst in output_rsts:
<% arr = '[PowerDomains-1:0] ' if rstmgr_is_array(rst['domains'], power_domains) else '' %>\
  % if rst['shadowed']:
    prim_mubi_pkg::mubi4_t ${arr}${rst['name']}_shadowed;
  % endif
    prim_mubi_pkg::mubi4_t ${arr}${rst['name']};
% endfor
  } rstmgr_rst_en_primary_t;

  // Each struct below holds all the reset asserted indications that a partition generates, before
  // the routing.
% for part in ('secondary', 'primary'):
  typedef struct packed {
  % for rst in output_rsts:
<% hosted = rstmgr_hosted_domains(rst, part)
arr = '[PowerDomains-1:0] ' if hosted and rstmgr_is_array(hosted, power_domains) else '' %>\
    % if hosted:
      % if rst['shadowed']:
    prim_mubi_pkg::mubi4_t ${arr}${rst['name']}_shadowed;
      % endif
    prim_mubi_pkg::mubi4_t ${arr}${rst['name']};
    % endif
  % endfor
  } rstmgr_rst_en_generated_${part}_t;

% endfor
  parameter int NumOutputRst = ${n_rst} * PowerDomains;

  // Signalling between the two partitions of the split reset manager.
  // Secondary (reset roots, always-on side) to primary
  typedef struct packed {
    // The reset roots, per power domain, that the primary partition's leaf resets have as parents.
% for root, domain in rstmgr_routed_roots(leaf_rsts):
    logic rst_${root}_n_${domain.lower()};
% endfor
    // The power manager's reset request, forwarded for the RESET_INFO logic.
    pwrmgr_pkg::pwr_rst_req_t pwr;
    // The aggregated errors of the leaf resets that the secondary partition hosts.
    logic cnsty_chk_err;
    logic fsm_err;
    // The resets that the secondary partition generates and the primary partition's power domain
    // uses.
% for r in routed_rsts('primary'):
    logic ${r};
% endfor
    // The reset asserted indications that the secondary partition generates. The primary partition
    // outputs them.
% for f, _, _ in rstmgr_rst_en_routed(output_rsts):
    prim_mubi_pkg::mubi4_t ${f};
% endfor
  } intraip_s2p_t;

  // Primary to secondary
  typedef struct packed {
% if routed_rsts('secondary'):
    // The resets that the primary partition generates and the secondary partition's power domain
    // uses.
  % for r in routed_rsts('secondary'):
    logic ${r};
  % endfor
% else:
    // Nothing flows to the secondary partition in this configuration. The reserved field keeps the
    // struct from being empty.
    logic reserved;
% endif
  } intraip_p2s_t;

  // cpu reset requests and status
  typedef struct packed {
    logic ndmreset_req;
  } rstmgr_cpu_t;

  // exported resets
% for intf, eps in export_rsts.items():
  typedef struct packed {
  % for ep, rsts in eps.items():
    % for rst in rsts:
    logic [PowerDomains-1:0] rst_${intf}_${ep}_${rst['name']}_n;
    % endfor
  % endfor
  } rstmgr_${intf}_out_t;
% endfor

  // default value for rstmgr_ast_rsp_t (for dangling ports)
  parameter rstmgr_cpu_t RSTMGR_CPU_DEFAULT = '{
    ndmreset_req: '0
  };

  // Enumeration for pwrmgr hw reset inputs
  import rstmgr_reg_pkg::NumTotalResets;
  localparam int ResetWidths = $clog2(NumTotalResets);
  typedef enum logic [ResetWidths-1:0] {
    ReqPeriResetIdx[0:${len(peri_reqs)-1}],
    % for req in (int_reqs + debug_reqs):
    ${f"Req{req['name']}ResetIdx"}${"" if loop.last else ","}
    % endfor
  } reset_req_idx_e;

  // Enumeration for reset info bit idx
  typedef enum logic [ResetWidths-1:0] {
    InfoPorIdx,
    InfoLowPowerExitIdx,
    InfoSwResetIdx,
    InfoPeriResetIdx[0:${len(peri_reqs)-1}],
    % for req in (int_reqs + debug_reqs):
    ${f"Info{req['name']}ResetIdx"}${"" if loop.last else ","}
    % endfor
  } reset_info_idx_e;


endpackage // rstmgr_pkg
