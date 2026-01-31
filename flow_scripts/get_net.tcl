# get_net_labels_from_top5pct_paths_v2.tcl
#
# Input : top5pct_worst_paths.txt (TSV): Startpoint \t Endpoint \t Slack
# Output: ./timing_reports/postroute/critical_nets.txt
#         ./timing_reports/postroute/net_labels.csv
#         ./timing_reports/postroute/critical_paths_summary.csv
#
# Works with your get_property syntax:
#   get_property [-object_type <type>] <object_or_name> <property>

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

# get_property wrapper that ALWAYS works with "name strings"
# obj_type: pin|port|net|path|point|cell|...
proc gp {obj_type obj prop} {
    # If obj is empty, return empty
    if {$obj eq ""} { return "" }
    # Use -object_type always (safe even if obj is already an object in many builds)
    return [get_property -object_type $obj_type $obj $prop]
}

# For startpoints it's usually a pin; for endpoints often a port.
proc resolve_from_object {s} {
    set name [strip_suffix_parens $s]

    # 1) try exact pin first
    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }

    # 2) wildcard pin (hier/prefix variants)
    set p [get_pins "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    # 3) fallback: port
    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    set prt [get_ports "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    return ""
}

proc resolve_to_object {s} {
    set name [strip_suffix_parens $s]

    # 1) try exact port first
    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    # 2) wildcard port (bus bits etc.)
    set prt [get_ports "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    # 3) fallback: pin
    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }

    set p [get_pins "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    return ""
}

proc pick_worst_path_by_slack {paths} {
    # paths are PathEnd objects or names; we treat them as names and use gp path
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

# Extract net names from a PathEnd (worst path)
# Uses: path.points -> point.pin -> get_nets -of_objects pin
proc add_nets_from_path {p critical_nets_var} {
    upvar $critical_nets_var critical_nets

    # points list
    set pts [gp path $p points]
    if {$pts eq ""} { return 0 }

    array set nets_on_path {}
    foreach pt $pts {
        # pt is PathRef
        set pin [gp point $pt pin]
        if {$pin eq ""} { continue }

        # get_nets returns names (strings) in your build
        set net_list [get_nets -of_objects $pin]
        if {[llength $net_list] == 0} { continue }

        set net_name [lindex $net_list 0]

        # filters
        if {[regexp {^(VDD|VSS|VPWR|VGND)} $net_name]} { continue }
        if {[regexp {^clk} $net_name]} { continue }

        set nets_on_path($net_name) 1
        set critical_nets($net_name) 1
    }
    return [array size nets_on_path]
}

# ---------------- main ----------------

# Read TSV
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
puts $sum "idx,start_raw,end_raw,from_obj,to_obj,slack_list,slack_found,n_nets_on_path,status"

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

    set from_obj [resolve_from_object $start_raw]
    set to_obj   [resolve_to_object $end_raw]

    if {$from_obj eq "" || $to_obj eq ""} {
        incr unresolved_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_obj\",\"$to_obj\",\"$slack_list\",,0,UNRESOLVED"
        continue
    }
    incr resolved_pairs

    # find paths (no -max_paths in your build)
    set paths {}
    if {[catch {
        set paths [find_timing_paths -corner $corner -path_delay max -from $from_obj -to $to_obj]
    } err]} {
        incr no_path_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_obj\",\"$to_obj\",\"$slack_list\",,0,FIND_FAIL"
        continue
    }

    if {[llength $paths] == 0} {
        incr no_path_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_obj\",\"$to_obj\",\"$slack_list\",,0,NO_PATH"
        continue
    }

    incr found_pairs
    set p [pick_worst_path_by_slack $paths]
    set slack_found [gp path $p slack]

    set n_nets [add_nets_from_path $p critical_nets]
    puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_obj\",\"$to_obj\",\"$slack_list\",$slack_found,$n_nets,OK"
}
close $sum

puts "Pairs in file: $total_pairs"
puts "Resolved pairs: $resolved_pairs"
puts "Unresolved pairs: $unresolved_pairs"
puts "Pairs with paths found: $found_pairs"
puts "Pairs with no path / failures: $no_path_pairs"
puts "Unique critical nets: [array size critical_nets]"
puts "Wrote summary: $out_summary"

# Write critical nets
set fo [open $out_nets w]
foreach n [lsort [array names critical_nets]] { puts $fo $n }
close $fo
puts "Wrote: $out_nets"

# Write net_labels.csv (over all nets in design)
set fo [open $out_csv w]
puts $fo "net_name,label"

foreach net_name [get_nets] {
    # net_name is already a name string
    if {[regexp {^(VDD|VSS|VPWR|VGND|VCC|GND)} $net_name]} { continue }

    if {[info exists critical_nets($net_name)]} {
        puts $fo "$net_name,1"
    } else {
        puts $fo "$net_name,0"
    }
}
close $fo
puts "Wrote: $out_csv"