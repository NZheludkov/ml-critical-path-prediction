# extract_endpoint_features_place.tcl
# Goal: Extract endpoint features at placement stage.
# Output: features/endpoint_features_place.csv with stable endpoint key = "inst/D"

if {![info exists stage]} { set stage "features" }
set out_dir "./$stage"
exec mkdir -p $out_dir
set out_csv "$out_dir/endpoint_features_place.csv"

# Same endpoint definition as labels
if {![info exists endpoint_pin_regex]} { set endpoint_pin_regex {\/D$} }

# You likely already have this variable in your flow; fallback if available:
if {![info exists db_units_per_micron]} {
    # if ord::dbu_per_micron exists in your build, uncomment:
    # set db_units_per_micron [ord::dbu_per_micron]
    # otherwise assume 1000 (common), but лучше задайте в вашем flow явно
    set db_units_per_micron 1000
}

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

proc collect_endpoint_pins {regex} {
    set eps {}
    foreach p [get_pins -hierarchical "*"] {
        set n [obj_full_name $p]
        if {[regexp $regex $n]} { lappend eps $p }
    }
    return $eps
}

# Parse instance name from "inst/pin"
proc pin_to_inst_name {pin_full_name} {
    set inst ""
    if {[regexp {^(.+)\/[^\/]+$} $pin_full_name -> inst]} { return $inst }
    return ""
}

# Return D-net ODB object and human name (net property "name")
proc pin_to_net {pin_obj} {
    set nl [get_nets -of_objects $pin_obj]
    if {[llength $nl] == 0} { return [list "" ""] }
    set net_obj [lindex $nl 0]
    set net_name [get_property -object_type net $net_obj name]
    return [list $net_obj $net_name]
}

# Compute bbox/hpwl proxy from ODB net term bbox (works at place)
proc odb_net_bbox_feats {net_obj db_units_per_micron} {
    if {$net_obj eq ""} { return [list 0 0 0 0 0 0] }
    set dn [sta::sta_to_db_net $net_obj]
    if {$dn eq ""} { return [list 0 0 0 0 0 0] }

    set bb [$dn getTermBBox]
    if {$bb eq ""} { return [list 0 0 0 0 0 0] }

    set xmin [expr {[$bb xMin] / double($db_units_per_micron)}]
    set ymin [expr {[$bb yMin] / double($db_units_per_micron)}]
    set xmax [expr {[$bb xMax] / double($db_units_per_micron)}]
    set ymax [expr {[$bb yMax] / double($db_units_per_micron)}]
    set dx [expr {$xmax - $xmin}]
    set dy [expr {$ymax - $ymin}]
    set hpwl [expr {$dx + $dy}]
    return [list $xmin $ymin $xmax $ymax $dx $dy $hpwl]
}

# Instance center (best-effort via ODB)
proc inst_center_xy {inst_name db_units_per_micron} {
    if {$inst_name eq ""} { return [list 0 0] }
    # Try to resolve instance as a cell object
    set inst_obj [get_cells $inst_name]
    if {[llength $inst_obj] == 0} {
        set inst_obj [get_cells -hierarchical $inst_name]
    }
    if {[llength $inst_obj] == 0} { return [list 0 0] }
    set inst_obj [lindex $inst_obj 0]

    # Try to get bbox via ODB conversion if available
    # Many builds have sta::sta_to_db_inst; if not, skip.
    set cx 0.0
    set cy 0.0
    if {![catch { set di [sta::sta_to_db_inst $inst_obj] } err] && $di ne ""} {
        set bb [$di getBBox]
        set cx [expr {( [$bb xMin] + [$bb xMax] ) / 2.0 / double($db_units_per_micron)}]
        set cy [expr {( [$bb yMin] + [$bb yMax] ) / 2.0 / double($db_units_per_micron)}]
        return [list $cx $cy]
    }

    # Fallback: no inst bbox available
    return [list $cx $cy]
}

# Count input pins of instance excluding clock pins
proc inst_pin_counts {inst_name} {
    set inst_obj [get_cells -hierarchical $inst_name]
    if {[llength $inst_obj] == 0} { return [list 0 0 0] }
    set inst_obj [lindex $inst_obj 0]
    set pins [get_pins -of_objects $inst_obj]
    set n_in 0
    set n_out 0
    set n_clk 0
    foreach p $pins {
        set dir [get_property -object_type pin $p direction]
        set n [obj_full_name $p]
        if {[regexp {\/CLK$} $n]} { incr n_clk; continue }
        if {$dir eq "input"} { incr n_in }
        if {$dir eq "output"} { incr n_out }
    }
    return [list $n_in $n_out $n_clk]
}

# ---- main ----
set eps [collect_endpoint_pins $endpoint_pin_regex]
puts "INFO: endpoints_found=[llength $eps]"

set fo [open $out_csv w]
puts $fo "endpoint,instance,dx,dy,hpwl,termCount,itermCount,btermCount,fanout_proxy,ff_x,ff_y,ff_in_pins,ff_out_pins,ff_clk_pins,is_port_net"

foreach ep $eps {
    set ep_name [obj_full_name $ep]
    set inst_name [pin_to_inst_name $ep_name]

    # D net
    lassign [pin_to_net $ep] net_obj net_name
    set is_port_net 0
    if {$net_name ne "" && [get_ports $net_name] ne ""} { set is_port_net 1 }

    # D-net ODB stats
    set termCount 0
    set itermCount 0
    set btermCount 0
    set fanout_proxy 0

    if {$net_obj ne ""} {
        set dn [sta::sta_to_db_net $net_obj]
        if {$dn ne ""} {
            set termCount [$dn getTermCount]
            set itermCount [llength [$dn getITerms]]
            set btermCount [llength [$dn getBTerms]]
            # crude fanout proxy: total terms - 1 (driver)
            set fanout_proxy [expr {max(0, $termCount - 1)}]
        }
    }

    # bbox features
    set xmin 0; set ymin 0; set xmax 0; set ymax 0; set dx 0; set dy 0; set hpwl 0
    if {$net_obj ne ""} {
        lassign [odb_net_bbox_feats $net_obj $db_units_per_micron] xmin ymin xmax ymax dx dy hpwl
    }

    # FF position + pin counts
    lassign [inst_center_xy $inst_name $db_units_per_micron] ff_x ff_y
    lassign [inst_pin_counts $inst_name] ff_in ff_out ff_clk

    puts $fo "\"$ep_name\",\"$inst_name\",$dx,$dy,$hpwl,$termCount,$itermCount,$btermCount,$fanout_proxy,$ff_x,$ff_y,$ff_in,$ff_out,$ff_clk,$is_port_net"
}
close $fo
puts "Wrote: $out_csv"
