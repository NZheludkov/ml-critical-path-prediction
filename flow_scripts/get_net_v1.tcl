# get_net_labels_from_top5pct_paths_v3_fullname.tcl
#
# Input : top5pct_worst_paths.txt (TSV): Startpoint \t Endpoint \t Slack
# Output: ./timing_reports/postroute/
#   - critical_nets.txt              (human net full names)
#   - net_labels.csv                 (net_full_name,label)
#   - critical_paths_summary.csv     (from/to + handles + found slack + nets count)

set infile  "top5pct_worst_paths.txt"
set corner  "ss_1p60v_m40c"

set out_dir "./timing_reports/postroute"
exec mkdir -p $out_dir

set out_nets    "$out_dir/critical_nets.txt"
set out_csv     "$out_dir/net_labels.csv"
set out_summary "$out_dir/critical_paths_summary.csv"

# ---------------- helpers ----------------

proc strip_suffix_parens {s} {
    regsub {\s*\(.*\)\s*$} $s "" out
    return [string trim $out]
}

# Always use get_property with -object_type (your STA requires it for name strings)
proc gp {obj_type obj prop} {
    if {$obj eq ""} { return "" }
    return [get_property -object_type $obj_type $obj $prop]
}

# Convert DB handle -> human full name.
# NOTE: get_full_name expects an object returned by get_nets/get_pins/get_ports,
# not a raw list; so we resolve 1 element and call get_full_name on it.
proc full_name_of {obj_type handle} {
    if {$handle eq ""} { return "" }
    if {$obj_type eq "net"}  {
        set o [lindex [get_nets  $handle] 0]
        if {$o eq ""} { return "" }
        return [get_full_name $o]
    }
    if {$obj_type eq "pin"}  {
        set o [lindex [get_pins  $handle] 0]
        if {$o eq ""} { return "" }
        return [get_full_name $o]
    }
    if {$obj_type eq "port"} {
        set o [lindex [get_ports $handle] 0]
        if {$o eq ""} { return "" }
        return [get_full_name $o]
    }
    # fallback: try direct (if supported)
    return ""
}

# Resolve FROM: prefer pin first (startpoints often pins)
proc resolve_from_object {s} {
    set name [strip_suffix_parens $s]

    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }

    set p [get_pins "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    set prt [get_ports "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    return ""
}

# Resolve TO: prefer port first (endpoints often ports)
proc resolve_to_object {s} {
    set name [strip_suffix_parens $s]

    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    set prt [get_ports "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }

    set p [get_pins "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    return ""
}

proc pick_worst_path_by_slack {paths} {
    set worst ""
    set worst_slack 1e99
    foreach p $paths {
        set s [gp path $p slack]
        if {$s < $worst_slack} {
            set worst_slack $s
            set worst $p
        }
    }
    return $worst
}

# Extract nets (human names) from a PathEnd, add to critical set.
proc add_nets_from_path {p critical_nets_var} {
    upvar $critical_nets_var critical_nets

    set pts [gp path $p points]
    if {$pts eq ""} { return 0 }

    array set nets_on_path {}
    foreach pt $pts {
        set pin_handle [gp point $pt pin]
        if {$pin_handle eq ""} { continue }

        # get_nets -of_objects returns net handles
        set net_list [get_nets -of_objects $pin_handle]
        if {[llength $net_list] == 0} { continue }

        set net_handle [lindex $net_list 0]

        # Convert handle -> human name
        set net_full [full_name_of net $net_handle]
        if {$net_full eq ""} {
            # fallback: if full_name fails, keep handle to not lose data
            set net_full $net_handle
        }

        # filters (apply on human name if possible)
        if {[regexp {^(VDD|VSS|VPWR|VGND)} $net_full]} { continue }
        if {[regexp {^clk} $net_full]} { continue }

        set nets_on_path($net_full) 1
        set critical_nets($net_full) 1
    }
    return [array size nets_on_path]
}

# ---------------- main ----------------

set fp [open $infile r]
set lines [split [read $fp] "\n"]
close $fp

array set critical_nets {}

set total_pairs 0
set resolved_pairs 0
set unresolved_pairs 0
set found_pairs 0
set no_path_pairs 0

set sum [open $out_summary w]
puts $sum "idx,start_raw,end_raw,from_handle,to_handle,from_full,to_full,slack_list,slack_found,n_nets_on_path,status"

set idx 0
foreach line $lines {
    set line [string trim $line]
    if {$line eq ""} { continue }
    if {[string match "Startpoint*" $line]} { continue }

    set f [split $line "\t"]
    if {[llength $f] < 2} { continue }

    set start_raw [string trim [lindex $f 0]]
    set end_raw   [string trim [lindex $f 1]]
    set slack_list ""
    if {[llength $f] >= 3} { set slack_list [string trim [lindex $f 2]] }

    incr total_pairs
    incr idx

    set from_handle [resolve_from_object $start_raw]
    set to_handle   [resolve_to_object $end_raw]

    if {$from_handle eq "" || $to_handle eq ""} {
        incr unresolved_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_handle\",\"$to_handle\",,,,,,UNRESOLVED"
        continue
    }
    incr resolved_pairs

    # Human-readable names for logging
    # Note: from could be pin or port; to could be port or pin.
    set from_full ""
    set to_full ""

    # Try as pin then port
    set from_full [full_name_of pin $from_handle]
    if {$from_full eq ""} { set from_full [full_name_of port $from_handle] }
    set to_full [full_name_of port $to_handle]
    if {$to_full eq ""} { set to_full [full_name_of pin $to_handle] }

    # Find all paths for this from/to
    set paths {}
    if {[catch {
        set paths [find_timing_paths -corner $corner -path_delay max -from $from_handle -to $to_handle]
    } err]} {
        incr no_path_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_handle\",\"$to_handle\",\"$from_full\",\"$to_full\",\"$slack_list\",,0,FIND_FAIL"
        continue
    }

    if {[llength $paths] == 0} {
        incr no_path_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_handle\",\"$to_handle\",\"$from_full\",\"$to_full\",\"$slack_list\",,0,NO_PATH"
        continue
    }

    incr found_pairs
    set p [pick_worst_path_by_slack $paths]
    set slack_found [gp path $p slack]

    set n_nets [add_nets_from_path $p critical_nets]

    puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_handle\",\"$to_handle\",\"$from_full\",\"$to_full\",\"$slack_list\",$slack_found,$n_nets,OK"
}
close $sum

puts "Pairs in file: $total_pairs"
puts "Resolved pairs: $resolved_pairs"
puts "Unresolved pairs: $unresolved_pairs"
puts "Pairs with paths found: $found_pairs"
puts "Pairs with no path / failures: $no_path_pairs"
puts "Unique critical nets (human names): [array size critical_nets]"
puts "Wrote summary: $out_summary"

# ---- Write critical nets (human) ----
set fo [open $out_nets w]
foreach n [lsort [array names critical_nets]] { puts $fo $n }
close $fo
puts "Wrote: $out_nets"

# ---- Write net_labels.csv for ALL nets (human) ----
# get_nets returns handles; we convert one-by-one via get_full_name.
set fo [open $out_csv w]
puts $fo "net_full_name,label"

foreach net_handle [get_nets] {
    set net_full [full_name_of net $net_handle]
    if {$net_full eq ""} {
        # fallback to handle
        set net_full $net_handle
    }

    if {[regexp {^(VDD|VSS|VPWR|VGND)} $net_full]} { continue }

    if {[info exists critical_nets($net_full)]} {
        puts $fo "$net_full,1"
    } else {
        puts $fo "$net_full,0"
    }
}
close $fo
puts "Wrote: $out_csv"