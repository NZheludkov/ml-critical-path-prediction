# get_net_labels_from_top5pct_paths_v4_netname_via_property.tcl

set infile  "./$stage/top5pct_worst_paths.txt"
set corner  "ss_1p60v_m40c"

set out_dir "."
exec mkdir -p $out_dir

set out_nets    "$out_dir/$stage/critical_nets.txt"
set out_csv     "$out_dir/$stage/net_labels.csv"
set out_summary "$out_dir/$stage/critical_paths_summary.csv"

# Extract the canonical object token from report text:
# "_13605_/Q (sky130...)" -> "_13605_/Q"
# "txoe (output)"         -> "txoe"
proc raw_to_token {raw} {
    set raw [string trim $raw]
    if {$raw eq ""} { return "" }
    # take everything before the first whitespace
    return [lindex [split $raw] 0]
}

# Keep for backward compatibility if needed elsewhere
proc strip_suffix_parens {s} {
    regsub {\s*\(.*\)\s*$} $s "" out
    return [string trim $out]
}

proc gp {obj_type obj prop} {
    if {$obj eq ""} { return "" }
    return [get_property -object_type $obj_type $obj $prop]
}

# Universal parser for top paths lines.
# Supports formats:
#  A) TSV:   start \t end \t slack
#  B) "print style":  <slack>  <start>  ->  <end>
#  C) table style:    <start>  <end>  <slack>
# Returns {start_raw end_raw slack} or {}.
proc parse_top5_line {line} {
    set line [string trim $line]
    if {$line eq ""} { return {} }
    if {[string match "Startpoint*" $line]} { return {} }
    if {[regexp {^-+$} $line]} { return {} }

    # ---- A) TSV ----
    if {[string first "\t" $line] >= 0} {
        set f [split $line "\t"]
        if {[llength $f] < 2} { return {} }
        set start_raw [string trim [lindex $f 0]]
        set end_raw   [string trim [lindex $f 1]]
        set slack ""
        if {[llength $f] >= 3} { set slack [string trim [lindex $f 2]] }
        return [list $start_raw $end_raw $slack]
    }

    # ---- B) "<slack>  <start>  ->  <end>" ----
    # Example: -0.4290  _13605_/Q (...)  ->  _14153_/D (...)
    if {[regexp {^(-?[0-9]+(?:\.[0-9]+)?)\s+(.+?)\s+->\s+(.+)$} $line -> slack start_raw end_raw]} {
        return [list [string trim $start_raw] [string trim $end_raw] [string trim $slack]]
    }

    # ---- C) "<start>  <end>  <slack>" (slack is last token) ----
    if {[regexp {^(.*\S)\s+(-?[0-9]+(?:\.[0-9]+)?)$} $line -> se slack]} {
        # split se into start/end by 2+ spaces OR by ') ' boundary
        set se [string trim $se]

        # try split at boundary between two "(...)" blocks
        if {[regexp {^(.+\))\s+(.+\))$} $se -> start_raw end_raw]} {
            return [list [string trim $start_raw] [string trim $end_raw] [string trim $slack]]
        }

        # fallback: split by 2+ spaces
        set parts [regexp -all -inline {\S.*?(?=\s{2,}|$)} $se]
        if {[llength $parts] >= 2} {
            set start_raw [string trim [lindex $parts 0]]
            set end_raw   [string trim [lindex $parts 1]]
            return [list $start_raw $end_raw [string trim $slack]]
        }
    }

    return {}
}


# If a line has start+end collapsed into start_raw and end_raw is empty,
# split it into two raws: "<...>)  <...>)"
# Returns {start_raw end_raw} or {} if cannot split.
proc split_collapsed_start_end {collapsed} {
    set s [string trim $collapsed]
    if {$s eq ""} { return {} }

    # Most robust: two "(...)" blocks
    if {[regexp {^(.+\))\s+(.+\))$} $s -> a b]} {
        return [list [string trim $a] [string trim $b]]
    }

    # Fallback: split by 2+ spaces
    set parts [regexp -all -inline {\S.*?(?=\s{2,}|$)} $s]
    if {[llength $parts] >= 2} {
        return [list [string trim [lindex $parts 0]] [string trim [lindex $parts 1]]]
    }

    return {}
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

proc resolve_from_object {raw} {
    set name [raw_to_token $raw]
    if {$name eq ""} { return "" }

    # If it looks like inst/pin, treat as pin
    if {[string first "/" $name] >= 0} {
      set p [get_pins -hierarchical $name]
        if {[llength $p] > 0} { return [lindex $p 0] }
        set p [get_pins $name]
        if {[llength $p] > 0} { return [lindex $p 0] }
        return ""
    }

    # Otherwise try ports then pins
    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }
    set prt [get_ports -hierarchical $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }
    set prt [get_ports -hierarchical "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }
    set p [get_pins -hierarchical $name]
    if {[llength $p] > 0} { return [lindex $p 0] }
    set p [get_pins -hierarchical "${name}*"]
    if {[llength $p] > 0} { return [lindex $p 0] }

    return ""
}

proc resolve_to_object {raw} {
    set name [raw_to_token $raw]
    if {$name eq ""} { return "" }

    # If it looks like inst/pin, treat as pin FIRST (important for FF/D)
    if {[string first "/" $name] >= 0} {
       set p [get_pins -hierarchical $name]
        if {[llength $p] > 0} { return [lindex $p 0] }
        set p [get_pins $name]
        if {[llength $p] > 0} { return [lindex $p 0] }
        return ""
    }

    # Otherwise try port first (endpoint can be output port in reg2out)
    set prt [get_ports $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }
    set prt [get_ports -hierarchical $name]
    if {[llength $prt] > 0} { return [lindex $prt 0] }
    set prt [get_ports -hierarchical "${name}*"]
    if {[llength $prt] > 0} { return [lindex $prt 0] }

    set p [get_pins $name]
    if {[llength $p] > 0} { return [lindex $p 0] }
    set p [get_pins -hierarchical $name]
    if {[llength $p] > 0} { return [lindex $p 0] }
    set p [get_pins -hierarchical "${name}*"]
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
puts $sum "idx,start_raw,end_raw,from_tok,to_tok,from_name,to_name,slack_list,slack_found,n_nets_on_path,status"


set idx 0
foreach line $lines {


# DEBUG counters
if {![info exists ::dbg_total]} {
    set ::dbg_total 0
    set ::dbg_parsed 0
    set ::dbg_skipped 0
}

incr ::dbg_total
if {$::dbg_total <= 5} {
    puts "RAW_LINE($::dbg_total)=<$line>"
}

set parsed [parse_top5_line $line]
if {[llength $parsed] == 0} {
    incr ::dbg_skipped
    if {$::dbg_skipped <= 5} {
        puts "PARSE_FAIL($::dbg_skipped)=<$line>"
    }
    continue
}
incr ::dbg_parsed
if {$::dbg_parsed <= 5} {
    puts "PARSED($::dbg_parsed): slack=<[lindex $parsed 2]> start=<[lindex $parsed 0]> end=<[lindex $parsed 1]>"
}

# and then set start_raw/end_raw/slack_list from parsed...
set start_raw  [lindex $parsed 0]
set end_raw    [lindex $parsed 1]
set slack_list [lindex $parsed 2]







    set line [string trim $line]
    if {$line eq ""} { continue }
    if {[string match "Startpoint*" $line]} { continue }

        set parsed [parse_top5_line $line]
        if {[llength $parsed] == 0} { continue }

# If end_raw is empty but start_raw contains both start and end, split it.
if {$end_raw eq ""} {
    set se [split_collapsed_start_end $start_raw]
    if {[llength $se] == 2} {
        set start_raw [lindex $se 0]
        set end_raw   [lindex $se 1]
    }
}

    incr idx

    set from_tok [raw_to_token $start_raw]
    set to_tok   [raw_to_token $end_raw]

    set from_obj [resolve_from_object $start_raw]
    set to_obj   [resolve_to_object $end_raw]


    if {$from_obj eq "" || $to_obj eq ""} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_tok\",\"$to_tok\",,,\"$slack_list\",,0,UNRESOLVED"
        continue
    }

    set from_name [obj_full_name $from_obj]
    set to_name   [obj_full_name $to_obj]

    # Guard: sometimes a bad resolve returns clock-like objects/names.
    if {[regexp -nocase {(^clk$|/CLK$)} $to_name]} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_tok\",\"$to_tok\",\"$from_name\",\"$to_name\",\"$slack_list\",,0,BAD_ENDPOINT_CLK"
        continue
    }


    set paths {}
    if {[catch {
        set paths [find_timing_paths -corner $corner -path_delay max -path_group reg2reg -from $from_obj -to $to_obj]
    } err]} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_tok\",\"$to_tok\",\"$from_name\",\"$to_name\",\"$slack_list\",,0,FIND_FAIL"
        continue
    }

    if {[llength $paths] == 0} {
        puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_tok\",\"$to_tok\",\"$from_name\",\"$to_name\",\"$slack_list\",,0,NO_PATH"
        continue
    }

    set p [pick_worst_path_by_slack $paths]
    set slack_found [gp path $p slack]
    set n_nets [add_nets_from_path_dbset $p critical_nets_db]

    puts $sum "$idx,\"$start_raw\",\"$end_raw\",\"$from_tok\",\"$to_tok\",\"$from_name\",\"$to_name\",\"$slack_list\",$slack_found,$n_nets,OK"
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