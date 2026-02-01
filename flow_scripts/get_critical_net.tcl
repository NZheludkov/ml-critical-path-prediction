# get_net_labels_from_top5pct_paths_v4_netname_via_property.tcl

set infile  "./$stage/top5pct_worst_paths.txt"
set corner  "ss_1p60v_m40c"

set out_dir "."
exec mkdir -p $out_dir

set out_nets    "$out_dir/$stage/critical_nets.txt"
set out_csv     "$out_dir/$stage/net_labels.csv"
set out_summary "$out_dir/$stage/critical_paths_summary.csv"

proc strip_suffix_parens {s} {
    regsub {\s*\(.*\)\s*$} $s "" out
    return [string trim $out]
}

proc gp {obj_type obj prop} {
    if {$obj eq ""} { return "" }
    return [get_property -object_type $obj_type $obj $prop]
}

# ---- Robust "human name" for net objects: ALWAYS via get_property -object_type net ----
proc net_full_name {net_obj} {
    if {$net_obj eq "" || $net_obj eq "NULL"} { return "" }
    # In your test: name==full_name==get_full_name, so this is reliable.
    set n [gp net $net_obj full_name]
    set n [string trim $n]
    if {$n eq "" || $n eq "NULL"} { return "" }
    return $n
}

# For pins/ports we can use get_full_name (one object)
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

# Store critical nets by DB id (stable); output by net_full_name()
proc add_nets_from_path_dbset {p critical_nets_db_var} {
    upvar $critical_nets_db_var critical_nets_db

    set pts [gp path $p points]
    if {$pts eq ""} { return 0 }

    array set nets_on_path_db {}
    foreach pt $pts {
        set pin [gp point $pt pin]
        if {$pin eq ""} { continue }

        set net_list [get_nets -of_objects $pin]
        if {[llength $net_list] == 0} { continue }

        set net_obj [lindex $net_list 0]
        if {$net_obj eq "" || $net_obj eq "NULL"} { continue }

        # Filter using the *human* net name, but keep DB id as key
        set net_fn [net_full_name $net_obj]
        if {$net_fn eq ""} { continue }
        if {[regexp {^(VDD|VSS|VPWR|VGND)} $net_fn]} { continue }
        if {[regexp -nocase {(^clk|clknet|/CLK$|_CLK$)} $net_fn]} { continue }

        set nets_on_path_db($net_obj) 1
        set critical_nets_db($net_obj) 1
    }
    return [array size nets_on_path_db]
}

# ---------------- main ----------------

set fp [open $infile r]
set lines [split [read $fp] "\n"]
close $fp

array set critical_nets_db {}

set sum [open $out_summary w]
puts $sum "idx,start_raw,end_raw,from_name,to_name,slack_list,slack_found,n_nets_on_path,status"

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

    incr idx

    set from_obj [resolve_from_object $start_raw]
    set to_obj   [resolve_to_object $end_raw]

    if {$from_obj eq "" || $to_obj eq ""} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",,,\"$slack_list\",,0,UNRESOLVED"
        continue
    }

    set from_name [obj_full_name $from_obj]
    set to_name   [obj_full_name $to_obj]

    set paths {}
    if {[catch {
        set paths [find_timing_paths -corner $corner -path_delay max -from $from_obj -to $to_obj]
    } err]} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_name\",\"$to_name\",\"$slack_list\",,0,FIND_FAIL"
        continue
    }

    if {[llength $paths] == 0} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_name\",\"$to_name\",\"$slack_list\",,0,NO_PATH"
        continue
    }

    set p [pick_worst_path_by_slack $paths]
    set slack_found [gp path $p slack]
    set n_nets [add_nets_from_path_dbset $p critical_nets_db]

    puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_name\",\"$to_name\",\"$slack_list\",$slack_found,$n_nets,OK"
}
close $sum
puts "Wrote summary: $out_summary"
puts "Unique critical nets (DB): [array size critical_nets_db]"

# ---- critical_nets.txt (human net names) ----
set fo [open $out_nets w]
set names {}
foreach net_obj [array names critical_nets_db] {
    set n [net_full_name $net_obj]
    if {$n eq ""} { continue }
    lappend names $n
}
foreach n [lsort -unique $names] { puts $fo $n }
close $fo
puts "Wrote: $out_nets"

# ---- net_labels.csv (human net names, label by DB membership) ----
set fo [open $out_csv w]
puts $fo "net_name,label"
foreach net_obj [get_nets] {
    set n [net_full_name $net_obj]
    if {$n eq ""} { continue }
    if {[regexp {^(VDD|VSS|VPWR|VGND)} $n]} { continue }

    if {[info exists critical_nets_db($net_obj)]} {
        puts $fo "$n,1"
    } else {
        puts $fo "$n,0"
    }
}
close $fo
puts "Wrote: $out_csv"