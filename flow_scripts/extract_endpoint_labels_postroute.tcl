# extract_endpoint_labels_postroute.tcl
# Goal: For each endpoint pin (default */D), find worst reg2reg path slack at postroute
# and write a ranking dataset: endpoint_name, inst_name, slack, rank, percentile, bucket.

# ---- user config ----
if {![info exists stage]}  { set stage "route_label" }
if {![info exists corner]} { set corner "ss_1p60v_m40c" }
if {![info exists path_group]} { set path_group "reg2reg" }

# Endpoint pin selection (Sky130 FFs have /D)
if {![info exists endpoint_pin_regex]} { set endpoint_pin_regex {\/D$} }

set out_dir "./$stage"
exec mkdir -p $out_dir
set out_csv "$out_dir/endpoint_slacks_postroute.csv"
set out_dbg "$out_dir/endpoint_slacks_debug.txt"

# ---- helpers ----
proc gp {obj_type obj prop} {
    if {$obj eq ""} { return "" }
    return [get_property -object_type $obj_type $obj $prop]
}

array set ::FULLNAME_CACHE {}
proc obj_full_name {obj} {
    if {$obj eq ""} { return "" }
    if {[info exists ::FULLNAME_CACHE($obj)]} { return $::FULLNAME_CACHE($obj) }
    set fn ""
    if {[catch { set fn [get_full_name $obj] } err]} { set fn "" }
    set fn [string trim $fn]
    if {$fn eq "" || $fn eq "NULL"} { set fn $obj }
    set ::FULLNAME_CACHE($obj) $fn
    return $fn
}

# Find the worst slack among paths returned
proc pick_worst_slack {paths} {
    set worst_slack 1e99
    set worst_path ""
    foreach p $paths {
        set s [gp path $p slack]
        if {$s eq ""} { continue }
        if {$s < $worst_slack} {
            set worst_slack $s
            set worst_path $p
        }
    }
    return [list $worst_path $worst_slack]
}

# Get endpoint pins list by scanning design pins: */D
proc collect_endpoint_pins {regex} {
    set eps {}
    foreach p [get_pins -hierarchical "*"] {
        set n [obj_full_name $p]
        if {[regexp $regex $n]} {
            lappend eps $p
        }
    }
    return $eps
}

# ---- main ----
set dbg [open $out_dbg w]
puts $dbg "corner=$corner path_group=$path_group endpoint_pin_regex=$endpoint_pin_regex"

set endpoints [collect_endpoint_pins $endpoint_pin_regex]
puts $dbg "endpoints_found=[llength $endpoints]"
puts "INFO: endpoints_found=[llength $endpoints] (regex=$endpoint_pin_regex)"

# Collect rows: {endpoint_full inst_full slack}
set rows {}

set n_ok 0
set n_nopath 0

foreach ep $endpoints {
    set ep_name [obj_full_name $ep]

    # Instance name (best-effort): parse from "inst/pin"
    set inst_name ""
    if {[regexp {^(.+)\/[^\/]+$} $ep_name -> inst_name]} {
        # ok
    } else {
        set inst_name ""
    }

    # Find worst reg2reg path to endpoint
    set paths {}
    if {[catch {
        set paths [find_timing_paths -corner $corner -path_delay max -path_group $path_group -to $ep]
    } err]} {
        puts $dbg "FIND_FAIL ep=$ep_name err=$err"
        incr n_nopath
        continue
    }

    if {[llength $paths] == 0} {
        puts $dbg "NO_PATH ep=$ep_name"
        incr n_nopath
        continue
    }

    lassign [pick_worst_slack $paths] worst_path slack
    if {$worst_path eq ""} {
        puts $dbg "NO_VALID_SLACK ep=$ep_name"
        incr n_nopath
        continue
    }

    lappend rows [list $ep_name $inst_name $slack]
    incr n_ok
}
puts $dbg "ok=$n_ok nopath=$n_nopath"
close $dbg

if {[llength $rows] == 0} {
    puts "ERROR: No endpoint rows collected. Check regex/path_group/corner."
    return
}

# Sort ascending slack (worst first)
set rows_sorted [lsort -real -increasing -index 2 $rows]
set total [llength $rows_sorted]

# Write CSV with rank/percentile/bucket
set fo [open $out_csv w]
puts $fo "endpoint,instance,worst_slack_ns,rank,percentile,bucket"
set rank 0
foreach r $rows_sorted {
    incr rank
    set ep_name   [lindex $r 0]
    set inst_name [lindex $r 1]
    set slack     [lindex $r 2]

    # percentile: 0 = worst, 1 = best
    set pct [expr {double($rank-1) / double($total-1)}]
    if {$total <= 1} { set pct 0.0 }

    # bucket for analysis (you can change thresholds)
    # 2 = violating, 1 = near-critical, 0 = safe
    set bucket 0
    if {$slack < 0.0} {
        set bucket 2
    } elseif {$slack < 0.1} {
        set bucket 1
    } else {
        set bucket 0
    }

    puts $fo "\"$ep_name\",\"$inst_name\",$slack,$rank,$pct,$bucket"
}
close $fo
puts "Wrote: $out_csv"
