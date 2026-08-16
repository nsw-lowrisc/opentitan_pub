# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

send_msg "Designcheck 1-1" INFO "Checking design"

# Check synchroniser placement, both flops should be in the same CLB
# ---------------------------------------------------------------------------
# CDC synchronizer placement check
#
# Verifies that for every prim_flop_2sync-style two-stage synchronizer bus,
# each bit's first-stage flop (u_sync_1/q_o_reg[N]) and second-stage flop
# (u_sync_2/q_o_reg[N]) have been placed in the same physical SITE (CLB
# slice), as ASYNC_REG is supposed to enforce.
# ---------------------------------------------------------------------------

# Clear any stale state from a previous run in this session
array unset bit_group_sites

set max_fails_to_report 10
set fail_count 0
set pass_count 0

# --- Step 1: gather every relevant flop primitive in the design, once -----
set all_flop_cells [get_cells -hierarchical -filter {
    PRIMITIVE_LEVEL == LEAF &&
    (REF_NAME == "FDRE" || REF_NAME == "FDCE" || REF_NAME == "FDPE" || REF_NAME == "FDSE")
}]
puts "Total flop cells found in design: [llength $all_flop_cells]"

# --- Step 2: keep only flops belonging to a u_sync_1 / u_sync_2 stage ------
set synchronizer_flop_cells {}
foreach flop_cell $all_flop_cells {
    if {[string match {*/u_sync_1/q_o_reg\[*\]} $flop_cell] ||
        [string match {*/u_sync_2/q_o_reg\[*\]} $flop_cell]} {
        lappend synchronizer_flop_cells $flop_cell
    }
}
puts "Synchronizer flop cells matched: [llength $synchronizer_flop_cells]"

# --- Step 3: group flops by (parent instance, bit index) -------------------
foreach flop_cell $synchronizer_flop_cells {

    set path_segments  [split $flop_cell /]
    set segment_count  [llength $path_segments]

    set stage_name     [lindex $path_segments [expr {$segment_count - 2}]]
    set parent_instance [join [lrange $path_segments 0 [expr {$segment_count - 3}]] /]

    if {![regexp {\[(\d+)\]$} $flop_cell -> bit_index]} {
        continue
    }

    set group_key "${parent_instance}|${bit_index}"

    set flop_site [get_property SITE $flop_cell]
    lappend bit_group_sites($group_key) [list $stage_name $flop_site $flop_cell]
}
puts "Number of bit-groups found: [array size bit_group_sites]"

# --- Step 4: check each group for a site mismatch --------------------------
foreach group_key [lsort [array names bit_group_sites]] {

    if {$fail_count >= $max_fails_to_report} {
        break
    }

    set stage_entries [set bit_group_sites($group_key)]

    set sites_in_group {}
    foreach stage_entry $stage_entries {
        lassign $stage_entry stage_name flop_site flop_cell
        lappend sites_in_group $flop_site
    }
    set unique_sites [lsort -unique $sites_in_group]

    if {[llength $unique_sites] > 1} {
        incr fail_count
        lassign [split $group_key |] parent_instance bit_index
        puts "FAIL #$fail_count: $parent_instance bit\[$bit_index\]"
        foreach stage_entry $stage_entries {
            lassign $stage_entry stage_name flop_site flop_cell
            puts "    $flop_cell  ($stage_name)  SITE=$flop_site"
        }
    } else {
        incr pass_count
    }
}

puts ""
puts "Checked [array size bit_group_sites] bit-groups: $pass_count PASS, $fail_count FAIL (fail reporting capped at $max_fails_to_report)"


# Ensure the design meets timing
set slack_ns [get_property SLACK [get_timing_paths -delay_type min_max]]
send_msg "Designcheck 1-2" INFO "Slack is ${slack_ns} ns."

if [expr {$slack_ns < 0}] {
  send_msg "Designcheck 1-3" ERROR "Timing failed. Slack is ${slack_ns} ns."
}

# Enable bitstream identification via USR_ACCESS register.
set_property BITSTREAM.CONFIG.USR_ACCESS TIMESTAMP [current_design]

# Generate a dummy MMI file (FIXME: temporary, to be removed).
# Args:
#   filename:            Path to the output file.
#   designtask_count:    A number used for logging with `send_msg`.
proc generate_mmi {filename designtask_count} {
    send_msg "${designtask_count}-1" INFO "Writing dummy MMI file to ${filename}"
    set workroot [file dirname [info script]]
    set filepath "${workroot}/${filename}"
    set fileout [open $filepath "w"]
    puts $fileout "This is a temporary dummy file to placate Bazel/CI whilst migrating to the bkdr_loader flow."
    puts $fileout "This file is not a valid MMI file, and should NOT be used as such."
    close $fileout
}

# Dump INIT_XX strings for the given BRAMs to an output file.
#
# In the output file, the BRAMs and their INIT_XX strings will be sorted in
# increasing order. This proc is a time-saver because the Vivado GUI's property
# viewer does not sort the INIT_XX strings numerically.
#
# Args:
#   filename:         Where to write
#   brams:            A list of BRAM cells.
#   designtask_count: A number used for logging with `send_msg`.
proc dump_init_strings {filename brams designtask_count} {
    # For each OTP BRAM, dump all the INIT_XX strings.
    send_msg "${designtask_count}-1" INFO "Dumping INIT_XX strings to ${filename}"

    set workroot [file dirname [info script]]
    set filepath "${workroot}/${filename}"
    set fileout [open $filepath "w"]

    foreach inst [lsort -dictionary $brams] {
        set bram [get_cells $inst]

        set loc [get_property LOC $bram]
        puts $fileout "LOC: $loc"

        set init_count 0
        while 1 {
            set key [format "INIT_%.2X" $init_count]
            if { [llength [list_property $bram $key]] eq 0 } {
                break
            }
            set val [get_property $key $bram]
            puts $fileout "$key $val"
            incr init_count
        }

        puts $fileout ""
    }
    close $fileout
    send_msg "${designtask_count}-4" INFO "INIT_XX strings dumped to ${filepath}"
}

set fpga_family [get_property FAMILY [get_parts [get_property PART [current_design]]]]

switch ${fpga_family} {
  kintex7 {
    set bram_regex "BMEM.*.*"
  }
  kintexu {
    set bram_regex "BLOCKRAM.*.*"
  }
  default {
    set bram_regex "BMEM.*.*"
  }
}
set mem_type_regex {(RAMB\d+)_(\w+)}

set gen_mem_info {{brams mem_type_regex fake_word_width addr_end_multiplier schema} {
  dict set mem_info brams $brams
  dict set mem_info mem_type_regex $mem_type_regex
  dict set mem_info fake_word_width $fake_word_width
  dict set mem_info addr_end_multiplier $addr_end_multiplier
  return [dict set mem_info schema $schema]
}}

# The scrambled Boot ROM is actually 39 bits wide, but we need to pretend that
# it's 40 bits, or else we will be unable to encode our ROM data in a MEM file
# that updatemem will understand.
#
# Suppose we did not pad the width, leaving it at 39 bits. Now, if we encode a
# word as a 10-digit hex string, updatemem would splice an additional zero bit
# into the bitstream because each hex digit is strictly 4 bits. If we wrote four
# words at a time, as a 39-digit hex string (39*4 is nicely divisible by 4),
# updatemem would fail to parse the hex string, saying something like "Data
# segment starting at 0x00000000, has exceeded data limits." The longest hex
# string it will accept is 16 digits, or 64 bits.
#
# A hack that works is to pretend the data width is actually 40 bits. Updatemem
# seems to write that extra zero bit into the ether without complaint.
set rom_brams [split [get_cells -hierarchical -filter " PRIMITIVE_TYPE =~ ${bram_regex} && NAME =~ *u_rom_ctrl*"] " "]
dict set memInfo rom [apply $gen_mem_info $rom_brams $mem_type_regex 40 1 "Processor"]

# OTP does not require faking the word width, but it has its own quirk. It seems
# each 22-bit OTP word is followed by 15 zero words. The MMI's <AddressSpace>
# and <AddressRange> tags need to account for this or else updatemem will think
# that its data input overruns the address space. The workaround is to pretend
# the address space is 16 times larger than we would normally compute.
set otp_brams [split [get_cells -hierarchical -filter " PRIMITIVE_TYPE =~ ${bram_regex} && NAME =~ *u_otp_macro*"] " "]
dict set memInfo otp [apply $gen_mem_info $otp_brams $mem_type_regex 0 16 "Processor"]

generate_mmi "memories.mmi" 1

# For debugging purposes, dump the INIT_XX strings for ROM and OTP.
dump_init_strings "rom_init_strings.txt" $rom_brams 3
dump_init_strings "otp_init_strings.txt" $otp_brams 4
