// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The indication checks of the single power-domain reset manager, for the resets that the primary
// partition generates. rstmgr_bind binds this interface to rstmgr_part_primary.
// rstmgr_rst_en_track_secondary_sva_if has the checks of the resets that the secondary partition
// generates.
<%
from topgen.lib import Name
from ipgen.manager_split import rstmgr_clocks, rstmgr_hosted_domains, rstmgr_is_array
part = 'primary'
part_clks = getattr(rstmgr_clocks(clk_freqs, leaf_rsts, rst_ni), part)

def sel(rst, domain):
  """Return the select of a power domain in this partition's struct field of a reset."""
  hosted = rstmgr_hosted_domains(rst, part)
  return f"[rstmgr_pkg::Domain{domain}Sel]" if rstmgr_is_array(hosted, power_domains) else ""

%>\

// This checks that the outgoing resets and the corresponding reset enable going to alert handler
// are shifted by a single clock cycle.
interface rstmgr_rst_en_track_primary_sva_if (
% for clk in part_clks:
  input logic clk_${clk}_i,
% endfor
  input logic rst_por_ni,
  input rstmgr_pkg::rstmgr_generated_primary_t resets_generated,
  input rstmgr_pkg::rstmgr_rst_en_generated_primary_t rst_en_generated
);
  localparam int DELAY = 1;

% for rst in output_rsts:
<% rst_camel_name = Name.to_camel_case(rst['name']) %>\
  % for domain in rstmgr_hosted_domains(rst, part):
<% s = sel(rst, domain) %>\
    % if rst['shadowed']:
  `ASSERT(D${domain.capitalize()}Rst${rst_camel_name}ShadowedEnTracksRst${rst_camel_name}ShadowedActive_A,
          $fell(resets_generated.rst_${rst['name']}_shadowed_n${s}) |-> ##[0:DELAY]
          rst_en_generated.${rst['name']}_shadowed${s} == prim_mubi_pkg::MuBi4True,
          clk_${rst['clock']}_i,
          !rst_por_ni)

  `ASSERT(D${domain.capitalize()}Rst${rst_camel_name}ShadowedEnTracksRst${rst_camel_name}ShadowedInactive_A,
          $rose(resets_generated.rst_${rst['name']}_shadowed_n${s}) |-> ##DELAY
          !resets_generated.rst_${rst['name']}_shadowed_n${s} ||
          rst_en_generated.${rst['name']}_shadowed${s} == prim_mubi_pkg::MuBi4False,
          clk_${rst['clock']}_i,
          !rst_por_ni)

    % else:
  `ASSERT(D${domain.capitalize()}Rst${rst_camel_name}EnTracksRst${rst_camel_name}Active_A,
          $fell(resets_generated.rst_${rst['name']}_n${s}) |-> ##[0:DELAY]
          rst_en_generated.${rst['name']}${s} == prim_mubi_pkg::MuBi4True,
          clk_${rst['clock']}_i,
          !rst_por_ni)

  `ASSERT(D${domain.capitalize()}Rst${rst_camel_name}EnTracksRst${rst_camel_name}Inactive_A,
          $rose(resets_generated.rst_${rst['name']}_n${s}) |-> ##DELAY
          !resets_generated.rst_${rst['name']}_n${s} ||
          rst_en_generated.${rst['name']}${s} == prim_mubi_pkg::MuBi4False,
          clk_${rst['clock']}_i,
          !rst_por_ni)

    % endif
  % endfor
% endfor
endinterface
