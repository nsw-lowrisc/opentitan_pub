# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# set the ASYN_REG attribute on all the synchronisers

# apply_async_reg.tcl
# Applies ASYNC_REG attribute to synchronizer flops inside every instance
# of prim_flop_2sync, regardless of instance name or hierarchy depth.
# This will force the placement of the flops together.

# ---------------------------------------------------------------------------
# Apply ASYNC_REG to every prim_flop_2sync instance's leaf flops.
# Single-pass version: avoids repeated -hierarchical searches per instance.
# ---------------------------------------------------------------------------

set target_module_name "prim_flop_2sync"

# --- Step 1: gather every relevant flop primitive in the design, once -----
set all_flop_cells [get_cells -hierarchical -filter {
    PRIMITIVE_LEVEL == LEAF &&
    (REF_NAME == "FDRE" || REF_NAME == "FDCE" || REF_NAME == "FDPE" || REF_NAME == "FDSE")
}]

# --- Step 2: gather every instance of the target module, once -------------
set synchronizer_instances [get_cells -hierarchical -filter "ORIG_REF_NAME == $target_module_name"]

# Build an O(1) lookup set of known instance paths, and an empty bucket
# for each one to collect its child flops into.
set known_instance_paths {}
foreach synchronizer_instance $synchronizer_instances {
    dict set known_instance_paths $synchronizer_instance 1
    dict set instance_to_flop_cells $synchronizer_instance {}
}

# --- Step 3: walk each flop's own ancestry upward to find its owning ------
#             instance, using exact dict lookups (no glob/string match,
#             so generate-loop bracketed indices like gen_x[3] are safe).
foreach flop_cell $all_flop_cells {
    set path_segments [split $flop_cell /]
    set segment_count [llength $path_segments]

    for {set ancestor_depth [expr {$segment_count - 2}]} {$ancestor_depth >= 0} {incr ancestor_depth -1} {
        set candidate_ancestor_path [join [lrange $path_segments 0 $ancestor_depth] /]
        if {[dict exists $known_instance_paths $candidate_ancestor_path]} {
            dict lappend instance_to_flop_cells $candidate_ancestor_path $flop_cell
            break
        }
    }
}

# --- Step 4: apply ASYNC_REG per instance and report the result -----------
foreach synchronizer_instance $synchronizer_instances {

    set flop_cells [dict get $instance_to_flop_cells $synchronizer_instance]

    if {[llength $flop_cells] == 0} {
        puts "WARNING: No flop cells found under $synchronizer_instance — check hierarchy depth"
        continue
    }

    set_property ASYNC_REG true $flop_cells
    puts "INFO: Applied ASYNC_REG to [llength $flop_cells] cell(s) in $synchronizer_instance"

    set applied_values [get_property ASYNC_REG $flop_cells]
    puts "    Results: $applied_values"
}
