## Copyright lowRISC contributors (OpenTitan project).
## Licensed under the Apache License, Version 2.0, see LICENSE for details.
## SPDX-License-Identifier: Apache-2.0

## Commonly used instances. Adapt only here if their location changes.

## Clock Signal
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports IO_CLK]

## Rename MMCM outputs for less bug-prone parsing.
## Some auto-derived clocks can have names that include brackets.
create_generated_clock -name clk_main [get_pins clkgen/pll/CLKOUT0]
create_generated_clock -name clk_io [get_pins clkgen/pll/CLKOUT2]
create_generated_clock -name clk_usb_48 [get_pins clkgen/pll/CLKOUT1]
create_generated_clock -name clk_aon [get_pins clkgen/pll/CLKOUT4]
create_generated_clock -name clk_main_div_4 [get_pins gen_bkdr.u_bufg_div_full/O]

# Create separate sets of clocks for the 48 MHz ext clock tree and the 96 MHz
# I/O clock tree. Then make them logically exclusive, so they don't produce
# invalid combinations.
# The 48 MHz ext clocks all have a _lc suffix.

# The derived clocks for IO are created in 2 stages
#   AST
#     First the internal or external clock is selected
#     The result can then be divided or past as is
#   Clock manager
#     3 clocks a re required IO, IO_DIV2, IO_DIV4
#                | IO | IO_DIV2 | IO_DIV4
# When internal  | 96 |    48   |   24
# When external  | 48 |    48   |   24
#
# So for the internal clock it is the IO root and the divisions in the clkmgr
# For the external clock it is root/2 for IO, IO = IO_DIV2 and IO/2 = IO_DIV4
# This means in the FPGA some of the stages are optimised away, however,
# Vivado will create a generated clock if there is a divide in the BUFG, if
# it is a n/1 then it will just propagate the clock name through. So each of the
# generated is renamed and the unwanted one is suppressed at the mux.
# NOTE this is just for timing

# IO clock select in the the AST

#create_generated_clock -name clk_io #    -source [get_pin ${clkgen}/CLKOUT2] #    -divide_by 1 #    $clk_io_src_pin
create_generated_clock -name clk_io_ext_lc [get_pins u_ast/u_ast_main/u_ast_clks_byp_main/u_no_scan_clk_src_io_d1ord2/gen_div_bufg.u_bufg_div_full/O]

# stop the slower external clock
set_clock_sense -stop_propagation -clocks clk_io_ext_lc [get_pins u_ast/u_ast_main/u_ast_clks_byp_main/u_no_scan_clk_src_io_d1ord2/gen_div_bufg.u_bufg_div_mux/O]

# IO clock select and division in the clkmgr

# Divide by 2

create_generated_clock -name clk_io_div2 -master_clock [get_clocks clk_io] [get_pins top_*/*_pd_aon/u_clkmgr/u_no_scan_io_div2_div/gen_div_bufg.u_bufg_div_full/O]
#create_generated_clock -name clk_io_div2_ext_lc #    -divide_by 1 #    -source $clk_io_src_pin #    [get_pins ${u_div2}/gen_div_bufg.u_bufg_div_stepdown/O]

# this time stop the faster external clock path
set_clock_sense -stop_propagation -clocks clk_io [get_pins top_*/*_pd_aon/u_clkmgr/u_no_scan_io_div2_div/gen_div_bufg.u_bufg_div_mux/O]

# Divide by 4

create_generated_clock -name clk_io_div4 -master_clock [get_clocks clk_io] [get_pins top_*/*_pd_aon/u_clkmgr/u_no_scan_io_div4_div/gen_div_bufg.u_bufg_div_full/O]
create_generated_clock -name clk_io_div4_ext_lc -master_clock [get_clocks clk_io] [get_pins top_*/*_pd_aon/u_clkmgr/u_no_scan_io_div4_div/gen_div_bufg.u_bufg_div_stepdown/O]

# this time stop the faster external clock path
set_clock_sense -stop_propagation -clocks clk_io_div4_ext_lc [get_pins top_*/*_pd_aon/u_clkmgr/u_no_scan_io_div4_div/gen_div_bufg.u_bufg_div_mux/O]

# These clocks are mutually exclusive
set_clock_groups -logically_exclusive -group [get_clocks {clk_io clk_io_div2 clk_io_div4}] -group [get_clocks {clk_io_ext_lc clk_io_div4_ext_lc}]


## USB
# USB input delay to accommodate T_FST (full-speed transition time) and the
# PHY's sampling logic. The PHY expects to only see up to one transient / fake
# SE0. The phase relationship with the PHY's sampling clock is arbitrary, but
# for simplicity, constrain the maximum path delay to something smaller than
# `T_sample - T_FST(max)` to help keep the P/N skew from slipping beyond one
# sample period.
set_input_delay -clock clk_usb_48 -min 3.000 [get_ports {IO_USB_DP_RX IO_USB_DN_RX IO_USB_D_RX}]
set_input_delay -clock clk_usb_48 -max -add_delay 17.000 [get_ports {IO_USB_DP_RX IO_USB_DN_RX IO_USB_D_RX}]

# USB output max skew constraint
# Use the output-enable as a "clock" and time the P/N relative to it. Keep the skew within T_FST.
create_generated_clock -name usb_embed_out_clk -source [get_pins clkgen/pll/CLKOUT1] -multiply_by 1 [get_ports IO_USB_OE_N]
set_output_delay -clock usb_embed_out_clk -min 7.000 [get_ports {IO_USB_DP_TX IO_USB_DN_TX}]
set_output_delay -clock usb_embed_out_clk -max -add_delay 14.000 [get_ports {IO_USB_DP_TX IO_USB_DN_TX}]

## Muxed I/Os

## JTAG clocks and I/O delays
# Create clocks for the various TAPs.
create_clock -period 100.000 -name jtag_tck -waveform {0.000 50.000} -add [get_ports IOR3]
#create_generated_clock -name lc_jtag_tck -source [get_ports IOR3] -divide_by 1 #    [get_pins ${u_pinmux}/u_pinmux_strap_sampling/u_pinmux_jtag_buf_lc/prim_clock_buf_tck/gen_fpga_buf.bufg_i/O]
#create_generated_clock -name rv_jtag_tck -source [get_ports IOR3] -divide_by 1 #    [get_pins ${u_pinmux}/u_pinmux_strap_sampling/u_pinmux_jtag_buf_rv/prim_clock_buf_tck/gen_fpga_buf.bufg_i/O]

# Assign input and output delays.
# Note that incidental combinatorial paths through the pinmux do not get removed
# from timing below, but the half cycle timing for JTAG leaves a fairly generous
# requirement. If the JTAG constraints need to be tightened and overly constrain
# the combinational port-to-port paths,
#   set_max_delay -datapath_only
# may be used to apply timing exceptions for those paths.
# However, remember that the input and output delays contribute to the path
# delay for such a case, so the constraint value for set_max_delay must
# accommodate them. In other words, for the constraint
#   set_max_delay -datapath_only -from [get_ports] -through ${combo_path_pin} #                 -to [get_ports] ${max_delay_value}
# ${max_delay_value} =
#     ${max_input_delay} + ${max_output_delay} + ${max_port_to_port_delay}
set_output_delay -clock jtag_tck -max -add_delay 10.000 [get_ports IOR1]
set_output_delay -clock jtag_tck -min -add_delay -5.000 [get_ports IOR1]
set_input_delay -clock jtag_tck -clock_fall -min -add_delay 0.000 [get_ports {IOR0 IOR2}]
set_input_delay -clock jtag_tck -clock_fall -max -add_delay 12.500 [get_ports {IOR0 IOR2}]

## SPI clocks
# Max board skew between signals
# Max board delay
# Board skew affects input path for sampling
# The board delay affects time remaining on the output path.

create_clock -period 80.000 -name clk_spi -waveform {0.000 40.000} -add [get_ports SPI_DEV_CLK]

create_generated_clock -name clk_spi_in -source [get_ports SPI_DEV_CLK] -divide_by 1 -add -master_clock clk_spi [get_pins top_*/*_pd_main/u_spi_device/u_clk_spi_in_buf/gen_fpga_buf.bufg_i/O]
create_generated_clock -name clk_spi_out -source [get_ports SPI_DEV_CLK] -divide_by 1 -invert -add -master_clock clk_spi [get_pins top_*/*_pd_main/u_spi_device/u_clk_spi_out_buf/gen_fpga_buf.bufg_i/O]

set_input_delay -clock clk_spi -clock_fall -min -add_delay -2.500 [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]
set_input_delay -clock clk_spi -clock_fall -max -add_delay 3.500 [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]

## For half-cycle
#set_output_delay -clock clk_spi -min ${spi_dev_out_hold}  ${spi_dev_data} -add_delay
#set_output_delay -clock clk_spi -max ${spi_dev_out_setup} ${spi_dev_data} -add_delay

## For full-cycle
set_output_delay -clock clk_spi -clock_fall -min -add_delay -3.000 [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]
set_output_delay -clock clk_spi -clock_fall -max -add_delay 6.700 [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]

# CSB must act as a clock, in addition to data and a reset.
# The waveform is semi-arbitrary: This choice shows that both edges happen near
# the falling edge of clk_spi. The source clock latency constraints then
# function like set_input_delay where SPI_DEV_CS_L acts as data.
create_clock -period 160.000 -name clk_spid_csb -waveform {40.000 120.000} [get_ports SPI_DEV_CS_L]
set_clock_latency -min -source -2.500 [get_ports SPI_DEV_CS_L]
set_clock_latency -max -source 3.500 [get_ports SPI_DEV_CS_L]

# CSB-clocked status bits to various negedge-triggered flops, especially in the
# serializer.
# Advance the hold edge by one cycle, since CSB changes nominally on the same
# edge as SPI_DEV_OUT_CLK, but SPI_DEV_OUT_CLK isn't actually toggling.
set_multicycle_path -hold -end -from [get_clocks clk_spid_csb] -to [get_clocks clk_spi_out] 1
# Because this section does full-cycle sampling, the same moving of the capture
# edge is needed for SPI_DEV_CSB_CLK -> SPI_DEV_D* hold analysis. The default
# falling edge of SPI_DEV_CLK would not be active.
set_multicycle_path -hold -end -from [get_clocks clk_spid_csb] -through [get_ports [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]] -to [get_clocks clk_spi] 1
# Relax the hold time constraint for the passthrough clock gate. Really this is
# to accommodate the gate for the inverted clock, which isn't active for the
# modes used for these constraints. However, it would be an okay outcome if the
# filter result reached the gate before even the 7th clock edge got out.
set_multicycle_path -hold -end 1 -from [get_clocks clk_spi] -to [get_pins -filter "DIRECTION == IN && IS_LEAF" -of_objects [get_nets -segments top_*/*_pd_main/u_spi_device/u_passthrough/sck_gate_en]]
# Since this section is for full-cycle sampling, move the capture edge out for
# data driven clk_spi_in. These cases would actually wait for the clk_spi_out
# edge to change the data on the port and get sampled by the host on the next
# clk_spi_out edge.
set_multicycle_path -setup -end -from [get_clocks clk_spi_in] -through [get_ports [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]] -to [get_clocks clk_spi] 2
set_multicycle_path -hold -end -from [get_clocks clk_spi_in] -through [get_ports [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]] -to [get_clocks clk_spi] 2

### SPI TPM constraints
#set spi_tpm_period 100.00
#create_clock -add -name clk_spi_tpm -period ${spi_tpm_period} [get_ports SPI_DEV_CLK]
#
#create_generated_clock -name clk_spi_tpm_in -divide_by 1 -add -master_clock clk_spi_tpm #    -source [get_ports SPI_DEV_CLK] #    [get_pins ${u_spi_device}/u_clk_spi_in_buf/gen_fpga_buf.bufg_i/O]
#create_generated_clock -name clk_spi_tpm_out -divide_by 1 -add -master_clock clk_spi_tpm #    -source [get_ports SPI_DEV_CLK] #    [get_pins ${u_spi_device}/u_clk_spi_out_buf/gen_fpga_buf.bufg_i/O] -invert
#
#set_input_delay -clock clk_spi_tpm -clock_fall -min ${spi_dev_in_delay_min} #    ${spi_dev_data} -add_delay
#set_input_delay -clock clk_spi_tpm -clock_fall -max ${spi_dev_in_delay_max} #    ${spi_dev_data} -add_delay
#
## TPM CSB
#set_input_delay -clock clk_spi_tpm -clock_fall -min ${spi_dev_in_delay_min} #    [get_ports ${all_muxed_ports}] -add_delay
#set_input_delay -clock clk_spi_tpm -clock_fall -max ${spi_dev_in_delay_max} #    [get_ports ${all_muxed_ports}] -add_delay
#
## Use half-cycle sampling to comply with TPM spec.
#set_output_delay -clock clk_spi_tpm -min ${spi_dev_out_hold}  ${spi_dev_data} -add_delay
#set_output_delay -clock clk_spi_tpm -max ${spi_dev_out_setup} ${spi_dev_data} -add_delay
#
## Relax the hold time constraint for the passthrough clock gate. Really this is
## to accommodate the gate for the inverted clock, which isn't active for the
## modes used for these constraints. However, it would be an okay outcome if the
## filter result reached the gate before even the 7th clock edge got out.
#set_multicycle_path -hold -end 1 -from [get_clocks clk_spi_tpm] #    -to [get_pins -filter "DIRECTION == IN && IS_LEAF" -of_objects #        [get_nets -segments ${u_spi_device}/u_passthrough/sck_gate_en]]


## SPI Passthrough constraints
create_generated_clock -name clk_spi_pt -source [get_ports SPI_DEV_CLK] -divide_by 1 -add -master_clock clk_spi [get_ports SPI_HOST_CLK]


set_output_delay -clock clk_spi_pt -min -add_delay -3.500 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3}]
set_output_delay -clock clk_spi_pt -max -add_delay 3.500 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3}]
set_output_delay -clock clk_spi_pt -min -add_delay -3.500 [get_ports SPI_HOST_CS_L]
set_output_delay -clock clk_spi_pt -max -add_delay 3.500 [get_ports SPI_HOST_CS_L]

set_input_delay -clock clk_spi_pt -clock_fall -min -add_delay 0.000 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3}]
set_input_delay -clock clk_spi_pt -clock_fall -max -add_delay 10.700 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3}]

set_multicycle_path -hold -end -from [get_clocks clk_spid_csb] -to [get_clocks clk_spi_pt] 1

## SPI Host constraints
# SPI Host clock origin buffer

# Even though it's 2x the max possible frequency, keep the peripheral clock
# frequency for the output. This will enable shifting the latch edge for hold
# analysis by the proper amount to effect "half-cycle sampling" of SPI.
create_generated_clock -name clk_spi_host0 -source [get_pins top_*/*_pd_aon/u_clkmgr/u_clk_io_peri_cg/gen_gate.u_bufgce/O] -divide_by 2 -add -master_clock clk_io [get_ports SPI_HOST_CLK]

# Multi-cycle path to adjust the hold edge, since launch and capture edges are
# opposite in the SPI_HOST_CLK domain.
set_multicycle_path -setup -start -from [get_clocks -of_objects [get_pins top_*/*_pd_aon/u_clkmgr/u_clk_io_peri_cg/gen_gate.u_bufgce/O]] -to [get_clocks clk_spi_host0] 1
set_multicycle_path -hold -start -from [get_clocks -of_objects [get_pins top_*/*_pd_aon/u_clkmgr/u_clk_io_peri_cg/gen_gate.u_bufgce/O]] -to [get_clocks clk_spi_host0] 1

# set multicycle path for data going from SPI_HOST_CLK to logic
# the SPI host logic will read these paths at "full cycle"
set_multicycle_path -setup -end -from [get_clocks clk_spi_host0] -to [get_clocks -of_objects [get_pins top_*/*_pd_aon/u_clkmgr/u_clk_io_peri_cg/gen_gate.u_bufgce/O]] 2
set_multicycle_path -hold -end -from [get_clocks clk_spi_host0] -to [get_clocks -of_objects [get_pins top_*/*_pd_aon/u_clkmgr/u_clk_io_peri_cg/gen_gate.u_bufgce/O]] 2

set_output_delay -clock clk_spi_host0 -min -add_delay -3.500 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3 SPI_HOST_CS_L}]
set_output_delay -clock clk_spi_host0 -max -add_delay 3.500 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3 SPI_HOST_CS_L}]
set_input_delay -clock clk_spi_host0 -clock_fall -min -add_delay 0.000 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3 SPI_HOST_CS_L}]
set_input_delay -clock clk_spi_host0 -clock_fall -max -add_delay 10.700 [get_ports {SPI_HOST_D0 SPI_HOST_D1 SPI_HOST_D2 SPI_HOST_D3 SPI_HOST_CS_L}]

## Set asynchronous clock groups
set_clock_groups -asynchronous -group [get_clocks sys_clk_pin] -group [get_clocks {clk_main clk_main_div_4}] -group [get_clocks {clk_usb_48 usb_embed_out_clk}] -group [get_clocks clk_aon] -group [get_clocks {clk_io clk_io_div2 clk_io_div4 clk_spi_host0}] -group [get_clocks {clk_spi clk_spi_in clk_spi_out clk_spi_pt clk_spid_csb}] -group [get_clocks jtag_tck]

# Set max delays between clocks that have interactions
# this can be reported with:
#     report_clock_interaction -delay_type min_max -significant_digits 3 -name timing_1
set_max_delay -datapath_only -from [get_clocks clk_aon] -to [get_clocks clk_io] 41.667
set_max_delay -datapath_only -from [get_clocks clk_aon] -to [get_clocks clk_io_div2] 83.333
set_max_delay -datapath_only -from [get_clocks clk_aon] -to [get_clocks clk_io_div4] 166.667
set_max_delay -datapath_only -from [get_clocks clk_aon] -to [get_clocks clk_main] 41.667
set_max_delay -datapath_only -from [get_clocks clk_aon] -to [get_clocks clk_usb_48] 20.833
set_max_delay -datapath_only -from [get_clocks clk_aon] -to [get_clocks jtag_tck] 100.000
set_max_delay -datapath_only -from [get_clocks clk_io] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks clk_io] -to [get_clocks clk_main] 41.667
set_max_delay -datapath_only -from [get_clocks clk_io_div2] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks clk_io_div2] -to [get_clocks clk_main] 41.667
set_max_delay -datapath_only -from [get_clocks clk_io_div2] -to [get_clocks jtag_tck] 100.000
set_max_delay -datapath_only -from [get_clocks clk_io_div4] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks clk_io_div4] -to [get_clocks clk_main] 41.667
set_max_delay -datapath_only -from [get_clocks clk_io_div4] -to [get_clocks clk_main_div_4] 166.667
set_max_delay -datapath_only -from [get_clocks clk_io_div4] -to [get_clocks clk_usb_48] 20.833
set_max_delay -datapath_only -from [get_clocks clk_io_div4] -to [get_clocks jtag_tck] 100.000
set_max_delay -datapath_only -from [get_clocks clk_io_div4] -to [get_clocks usb_embed_out_clk] 20.833
set_max_delay -datapath_only -from [get_clocks clk_main] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks clk_main] -to [get_clocks clk_io] 41.667
set_max_delay -datapath_only -from [get_clocks clk_main] -to [get_clocks clk_io_div2] 83.333
set_max_delay -datapath_only -from [get_clocks clk_main] -to [get_clocks clk_io_div4] 166.667
set_max_delay -datapath_only -from [get_clocks clk_main] -to [get_clocks clk_usb_48] 20.833
set_max_delay -datapath_only -from [get_clocks clk_main] -to [get_clocks jtag_tck] 100.000
set_max_delay -datapath_only -from [get_clocks clk_main_div_4] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks clk_main_div_4] -to [get_clocks clk_io_div2] 83.333
set_max_delay -datapath_only -from [get_clocks clk_main_div_4] -to [get_clocks clk_io_div4] 166.667
set_max_delay -datapath_only -from [get_clocks clk_main_div_4] -to [get_clocks jtag_tck] 100.000
set_max_delay -datapath_only -from [get_clocks clk_usb_48] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks clk_usb_48] -to [get_clocks clk_io_div4] 166.667
set_max_delay -datapath_only -from [get_clocks clk_usb_48] -to [get_clocks clk_main] 41.667
set_max_delay -datapath_only -from [get_clocks jtag_tck] -to [get_clocks clk_aon] 4000.000
set_max_delay -datapath_only -from [get_clocks jtag_tck] -to [get_clocks clk_io_div2] 83.333
set_max_delay -datapath_only -from [get_clocks jtag_tck] -to [get_clocks clk_io_div4] 166.667
set_max_delay -datapath_only -from [get_clocks jtag_tck] -to [get_clocks clk_main] 41.667
set_max_delay -datapath_only -from [get_clocks jtag_tck] -to [get_clocks clk_main_div_4] 166.667
set_max_delay -datapath_only -from [get_clocks jtag_tck] -to [get_clocks clk_usb_48] 20.833


## TPM and non-TPM modes can't be active simultaneously
#set_clock_groups -physically_exclusive #    -group {clk_spi clk_spi_in clk_spi_out clk_spi_pt clk_spid_csb} #    -group {clk_spi_tpm clk_spi_tpm_in clk_spi_tpm_out}

# CSB and clocks are not active simultaneously, and CSB does not actually sample
# data from these clocks.
set_clock_groups -logically_exclusive -group clk_spi -group clk_spid_csb

# CSB to SPI_DEV output enables. Primarily affects generic mode with CPHA=0
# and the first bit.
# Because SPI_DEV_CS_L is a clock pin, various constraint styles will not take.
# Use output delay to constrain the allowed CSB-to-Q outputs.
set_output_delay -clock clk_spid_csb -min -add_delay 5.000 [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]
set_output_delay -clock clk_spid_csb -max -add_delay 50.000 [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}]

# Then mark the paths using other clocks as false paths. CSB does not actually
# sample these clocks.
set_false_path -from [get_clocks {clk_spi_in clk_spi_out clk_spi_pt}] -through [get_ports {SPI_DEV_D0 SPI_DEV_D1 SPI_DEV_D2 SPI_DEV_D3}] -to [get_clocks clk_spid_csb]

# CSB-clocked status bits to various negedge-triggered flops, especially in the
# serializer. Also may include the path to something for passthrough...
# Advance the hold edge by one cycle, since CSB changes nominally on the same
# edge as clk_spi_out, but clk_spi_out isn't actually toggling.
#set_multicycle_path -hold -end -from [get_clocks clk_spid_csb] #    -to [get_clocks clk_spi_out] 1
#set_multicycle_path -hold -end -from [get_clocks clk_spi_tpm] #    -through [get_ports ${all_muxed_ports}] #    -to [get_clocks clk_spi_tpm_out] 1


## The usb calibration handling inside ast is assumed to be async to the outside world
## even though its interface is also a usb clock.
set_false_path -from [get_clocks clk_usb_48] -to [get_pins {u_ast/u_ast_main/u_usb_clk/u_ref_pulse_sync/u_sync*/u_sync_1/q_o_reg[0]/D}]

