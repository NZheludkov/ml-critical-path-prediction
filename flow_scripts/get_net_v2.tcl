# get_net_labels_from_top5pct_paths_fullnames.tcl
#
# Input : top5pct_worst_paths.txt (TSV): Startpoint \t Endpoint \t Slack  (human names with optional "(...)")
# Output: ./timing_reports/postroute/
#   - critical_nets_fullname.txt
#   - net_labels_fullname.csv
#   - critical_paths_summary_fullname.csv
#
# Notes:
#   - Your tool returns DB ids like _..._p_Net for get_nets/get_ports/get_pins.
#   - We convert DB ids -> human names using get_full_name, one-by-one (with caching).

set infile  "top5pct_worst_paths.txt"
set corner  "ss_1p60v_m40c"

set out_dir "./timing_reports/postroute"
exec mkdir -p $out_dir

set out_nets    "$out_dir/critical_nets_fullname.txt"
set out_csv     "$out_dir/net_labels_fullname.csv"
set out_summary "$out_dir/critical_paths_summary_fullname.csv"

# ---------------- helpers ----------------

proc strip_suffix_parens {s} {
    regsub {\s*\(.*\)\s*$} $s "" out
    return [string trim $out]
}

# Cache: db_id -> full_name
array set ::FULLNAME_CACHE {}

proc to_full_name {obj} {
    # Convert a single DB object id to human-readable full name
    # Uses caching to avoid repeated get_full_name calls.
    if {$obj eq ""} { return "" }
    if {[info exists ::FULLNAME_CACHE($obj)]} { return $::FULLNAME_CACHE($obj) }

    # get_full_name may throw for some objects; guard it
    set fn ""
    if {[catch { set fn [get_full_name $obj] } err]} {
        # fallback: keep raw id if conversion fails
        set fn $obj
    }
    set ::FULLNAME_CACHE($obj) $fn
    return $fn
}

# Resolve Startpoint/Endpoint string (human) -> DB object (pin/port)
proc resolve_from_object {s} {
    set name [strip_suffix_parens $s]

    # pin first for from
    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }
    set p [get_pins "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    # fallback port
    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }
    set prt [get_ports "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    return ""
}

proc resolve_to_object {s} {
    set name [strip_suffix_parens $s]

    # port first for to
    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }
    set prt [get_ports "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    # fallback pin
    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }
    set p [get_pins "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    return ""
}

# get_property wrapper (your tool requires -object_type if object is a name;
# here we pass DB ids, but keeping explicit object_type is safe)
proc gp {obj_type obj prop} {
    if {$obj eq ""} { return "" }
    return [get_property -object_type $obj_type $obj $prop]
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

# Extract nets from a PathEnd, store by FULL NAME
proc add_nets_from_path_fullname {p critical_nets_var} {
    upvar $critical_nets_var critical_nets

    set pts [gp path $p points]
    if {$pts eq ""} { return 0 }

    array set nets_on_path {}
    foreach pt $pts {
        set pin [gp point $pt pin]
        if {$pin eq ""} { continue }

        # returns net DB objects
        set net_list [get_nets -of_objects $pin]
        if {[llength $net_list] == 0} { continue }

        set net_obj [lindex $net_list 0]
        set net_fn  [to_full_name $net_obj]

        # filters on human name
        if {[regexp {^(VDD|VSS|VPWR|VGND)} $net_fn]} { continue }
        if {[regexp {^clk} $net_fn]} { continue }

        set nets_on_path($net_fn) 1
        set critical_nets($net_fn) 1
    }
    return [array size nets_on_path]
}

# ---------------- main ----------------

# Read TSV
set fp [open $infile r]
set lines [split [read $fp] "\n"]
close $fp

array set critical_nets {}  ;# key = net full_name

set total_pairs 0
set resolved_pairs 0
set unresolved_pairs 0
set found_pairs 0
set no_path_pairs 0

set sum [open $out_summary w]
puts $sum "idx,start_raw,end_raw,from_full_name,to_full_name,slack_list,slack_found,n_nets_on_path,status"

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
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",,,\"$slack_list\",,0,UNRESOLVED"
        continue
    }
    incr resolved_pairs

    set from_fn [to_full_name $from_obj]
    set to_fn   [to_full_name $to_obj]

    # Find paths
    set paths {}
    if {[catch {
        set paths [find_timing_paths -corner $corner -path_delay max -from $from_obj -to $to_obj]
    } err]} {
        incr no_path_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_fn\",\"$to_fn\",\"$slack_list\",,0,FIND_FAIL"
        continue
    }

    if {[llength $paths] == 0} {
        incr no_path_pairs
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_fn\",\"$to_fn\",\"$slack_list\",,0,NO_PATH"
        continue
    }

    incr found_pairs
    set p [pick_worst_path_by_slack $paths]
    set slack_found [gp path $p slack]

    set n_nets [add_nets_from_path_fullname $p critical_nets]
    puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_fn\",\"$to_fn\",\"$slack_list\",$slack_found,$n_nets,OK"
}
close $sum

puts "Pairs in file: $total_pairs"
puts "Resolved pairs: $resolved_pairs"
puts "Unresolved pairs: $unresolved_pairs"
puts "Pairs with paths found: $found_pairs"
puts "Pairs with no path / failures: $no_path_pairs"
puts "Unique critical nets (full names): [array size critical_nets]"
puts "Wrote summary: $out_summary"

# Write critical nets full names
set fo [open $out_nets w]
foreach n [lsort [array names critical_nets]] { puts $fo $n }
close $fo
puts "Wrote: $out_nets"

# Write net_labels_fullname.csv over ALL nets (convert each net DB id -> full name)
set fo [open $out_csv w]
puts $fo "net_full_name,label"

foreach net_obj [get_nets] {
    set net_fn [to_full_name $net_obj]

    if {[regexp {^(VDD|VSS|VPWR|VGND)} $net_fn]} { continue }

    if {[info exists critical_nets($net_fn)]} {
        puts $fo "\"$net_fn\",1"
    } else {
        puts $fo "\"$net_fn\",0"
    }
}
close $fo
puts "Wrote: $out_csv"