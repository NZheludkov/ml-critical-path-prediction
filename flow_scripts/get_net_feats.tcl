# extract_net_features_place_v1_2.tcl
#
# Additions vs v1.1:
#   - sink spread statistics (mean/std/min/max for x,y)
#   - centroid distance features
#   - distance percentiles (p50/p90/p95) driver->sinks
#   - quadrant histogram of sinks relative to net bbox center
#   - area features from instance bbox (driver + sinks): sum/mean/max/std + class sums

set nets [get_full_name_list [get_nets *]]
set idx1 [lsearch $nets "VDD"]
set idx2 [lsearch $nets "VSS"]
set nets [lreplace $nets $idx1 $idx1]
set human_nets $nets

set out_dir "./features"
exec mkdir -p $out_dir
set out_csv "$out_dir/net_features_place.csv"

if {![info exists db_units_per_micron]} {
    if {[llength [info commands ord::dbu_per_micron]]} {
        set db_units_per_micron [ord::dbu_per_micron]
    } else {
        set db_units_per_micron 1000.0
    }
}

proc um {v dbu_per_um} { expr {double($v)/double($dbu_per_um)} }

proc bbox_um {bb dbu_per_um} {
    set xmin [um [$bb xMin] $dbu_per_um]
    set ymin [um [$bb yMin] $dbu_per_um]
    set xmax [um [$bb xMax] $dbu_per_um]
    set ymax [um [$bb yMax] $dbu_per_um]
    return [list $xmin $ymin $xmax $ymax]
}

proc inst_center_um {inst dbu_per_um} {
    set bb [$inst getBBox]
    set x [expr {0.5*([$bb xMin]+[$bb xMax]) / double($dbu_per_um)}]
    set y [expr {0.5*([$bb yMin]+[$bb yMax]) / double($dbu_per_um)}]
    return [list $x $y]
}

proc inst_area_um2 {inst dbu_per_um} {
    set bb [$inst getBBox]
    set w [expr {([$bb xMax]-[$bb xMin]) / double($dbu_per_um)}]
    set h [expr {([$bb yMax]-[$bb yMin]) / double($dbu_per_um)}]
    if {$w < 0} { set w 0 }
    if {$h < 0} { set h 0 }
    return [expr {$w*$h}]
}

proc is_ff_master {mname} { return [expr {[regexp {__df} $mname] || [regexp {dff} $mname]}] }
proc is_buf_master {mname} { return [regexp {__buf_} $mname] }
proc is_inv_master {mname} { return [regexp {__inv_} $mname] }
proc is_clkbuf_master {mname} { return [regexp {__clkbuf_} $mname] }

proc is_clock_like_name {n} { return [regexp -nocase {(^clk|clk$|clock)} $n] }
proc is_reset_like_name {n} { return [regexp -nocase {(rst|reset)} $n] }
proc is_enable_like_name {n} { return [regexp -nocase {(en$|enable|ce)} $n] }
proc is_bus_bit_name {n} { return [regexp {\[[0-9]+\]} $n] }

proc csv_escape {s} {
    if {$s eq ""} { return "\"\"" }
    set s [string map {"\"" "\"\""} $s]
    return "\"$s\""
}

proc list_mean {lst} {
    set n [llength $lst]
    if {$n == 0} { return "" }
    set sum 0.0
    foreach v $lst { set sum [expr {$sum + double($v)}] }
    return [expr {$sum/double($n)}]
}

proc list_std {lst mean} {
    set n [llength $lst]
    if {$n < 2 || $mean eq ""} { return "" }
    set s2 0.0
    foreach v $lst {
        set dv [expr {double($v) - double($mean)}]
        set s2 [expr {$s2 + $dv*$dv}]
    }
    # population std (divide by n). If you want sample std: divide by (n-1)
    return [expr {sqrt($s2/double($n))}]
}

proc list_min {lst} {
    if {[llength $lst] == 0} { return "" }
    set m [lindex $lst 0]
    foreach v $lst { if {double($v) < double($m)} { set m $v } }
    return $m
}

proc list_max {lst} {
    if {[llength $lst] == 0} { return "" }
    set m [lindex $lst 0]
    foreach v $lst { if {double($v) > double($m)} { set m $v } }
    return $m
}

proc list_percentile {lst p} {
    # p in [0..100], nearest-rank on sorted list
    set n [llength $lst]
    if {$n == 0} { return "" }
    set sorted [lsort -real $lst]
    if {$p <= 0} { return [lindex $sorted 0] }
    if {$p >= 100} { return [lindex $sorted end] }
    set rank [expr {int(ceil(($p/100.0)*$n)) - 1}]
    if {$rank < 0} { set rank 0 }
    if {$rank >= $n} { set rank [expr {$n-1}] }
    return [lindex $sorted $rank]
}

proc extract_one_net_features {net_name dbu_per_um} {
    set feat [dict create]
    dict set feat net_name $net_name

    set sta_net [get_nets $net_name]
    if {$sta_net eq ""} {
        dict set feat status "NET_NOT_FOUND"
        return $feat
    }
    dict set feat net_dbid $sta_net

    set dn [sta::sta_to_db_net $sta_net]
    if {$dn eq ""} {
        dict set feat status "ODB_NET_NOT_FOUND"
        return $feat
    }
    dict set feat odb_net $dn
    dict set feat status "OK"

    dict set feat term_count [$dn getTermCount]
    set iterms [$dn getITerms]
    set bterms [$dn getBTerms]
    dict set feat iterm_count [llength $iterms]
    dict set feat bterm_count [llength $bterms]
    dict set feat has_bterm [expr {[llength $bterms] > 0}]

    # net bbox/geometry
    set bb [$dn getTermBBox]
    lassign [bbox_um $bb $dbu_per_um] xmin ymin xmax ymax
    set dx [expr {$xmax-$xmin}]
    set dy [expr {$ymax-$ymin}]
    set cx [expr {0.5*($xmin+$xmax)}]
    set cy [expr {0.5*($ymin+$ymax)}]

    dict set feat bbox_xmin $xmin
    dict set feat bbox_ymin $ymin
    dict set feat bbox_xmax $xmax
    dict set feat bbox_ymax $ymax
    dict set feat bbox_dx $dx
    dict set feat bbox_dy $dy
    dict set feat hpwl [expr {$dx+$dy}]
    dict set feat bbox_area [expr {$dx*$dy}]
    dict set feat bbox_perimeter [expr {2.0*($dx+$dy)}]
    dict set feat bbox_cx $cx
    dict set feat bbox_cy $cy
    dict set feat bbox_aspect [expr {$dx/($dy+1e-9)}]

    # counts / roles
    set num_drivers 0
    set num_sinks 0
    set num_inout 0
    set num_port_drivers 0
    set num_port_sinks 0

    # type/class counts
    set driver_is_ff_q 0
    set num_ff_sinks_d 0

    set num_buf_drivers 0
    set num_inv_drivers 0
    set num_clkbuf_drivers 0
    set num_buf_sinks 0
    set num_inv_sinks 0

    # coordinates + areas
    set driver_xy ""
    set driver_area ""
    set sink_xs {}
    set sink_ys {}
    set sink_distances {}     ;# manhattan driver->sink
    set sink_areas {}         ;# area per sink inst
    set sink_area_sum 0.0
    set sink_area_ff_sum 0.0
    set sink_area_buf_sum 0.0
    set sink_area_inv_sum 0.0

    # quadrant counts relative to net bbox center
    set q1 0 ;# x>=cx, y>=cy
    set q2 0 ;# x< cx, y>=cy
    set q3 0 ;# x< cx, y< cy
    set q4 0 ;# x>=cx, y< cy

    # --- ITerms (internal instance pins) ---
    foreach it $iterms {
        set mterm [$it getMTerm]
        set io [$mterm getIoType]     ;# INPUT/OUTPUT/INOUT
        set pin_name [$mterm getName]
        set inst [$it getInst]
        set master [[$inst getMaster] getName]

        if {$io eq "OUTPUT"} {
            incr num_drivers

            if {$driver_xy eq ""} {
                set driver_xy [inst_center_um $inst $dbu_per_um]
                set driver_area [inst_area_um2 $inst $dbu_per_um]
            }

            if {[is_ff_master $master] && ($pin_name eq "Q")} { set driver_is_ff_q 1 }
            if {[is_buf_master $master]} { incr num_buf_drivers }
            if {[is_inv_master $master]} { incr num_inv_drivers }
            if {[is_clkbuf_master $master]} { incr num_clkbuf_drivers }

        } elseif {$io eq "INPUT"} {
            incr num_sinks

            set xy [inst_center_um $inst $dbu_per_um]
            lassign $xy sx sy
            lappend sink_xs $sx
            lappend sink_ys $sy

            # quadrant
            if {$sx >= $cx && $sy >= $cy} {
                incr q1
            } elseif {$sx < $cx && $sy >= $cy} {
                incr q2
            } elseif {$sx < $cx && $sy < $cy} {
                incr q3
            } else {
                incr q4
            }

            # area
            set a [inst_area_um2 $inst $dbu_per_um]
            lappend sink_areas $a
            set sink_area_sum [expr {$sink_area_sum + $a}]

            # class areas
            if {[is_ff_master $master] && ($pin_name eq "D")} {
                incr num_ff_sinks_d
                set sink_area_ff_sum [expr {$sink_area_ff_sum + $a}]
            }
            if {[is_buf_master $master]} {
                incr num_buf_sinks
                set sink_area_buf_sum [expr {$sink_area_buf_sum + $a}]
            }
            if {[is_inv_master $master]} {
                incr num_inv_sinks
                set sink_area_inv_sum [expr {$sink_area_inv_sum + $a}]
            }
        } elseif {$io eq "INOUT"} {
            incr num_inout
        }
    }

    # --- BTerms (ports) ---
    foreach bt $bterms {
        set io [$bt getIoType]
        if {$io eq "INPUT"}  { incr num_drivers; incr num_port_drivers }
        if {$io eq "OUTPUT"} { incr num_sinks;   incr num_port_sinks }
        if {$io eq "INOUT"}  { incr num_inout }
    }

    dict set feat num_drivers $num_drivers
    dict set feat num_sinks   $num_sinks
    dict set feat num_inout   $num_inout
    dict set feat fanout      $num_sinks
    dict set feat has_multiple_drivers [expr {$num_drivers > 1}]
    dict set feat num_port_drivers $num_port_drivers
    dict set feat num_port_sinks   $num_port_sinks

    dict set feat driver_is_ff_q $driver_is_ff_q
    dict set feat num_ff_sinks_d $num_ff_sinks_d
    dict set feat is_reg2reg_candidate [expr {$driver_is_ff_q && ($num_ff_sinks_d > 0)}]

    dict set feat num_buf_drivers $num_buf_drivers
    dict set feat num_inv_drivers $num_inv_drivers
    dict set feat num_clkbuf_drivers $num_clkbuf_drivers
    dict set feat num_buf_sinks $num_buf_sinks
    dict set feat num_inv_sinks $num_inv_sinks

    dict set feat driver_is_buf   [expr {$num_buf_drivers > 0}]
    dict set feat driver_is_inv   [expr {$num_inv_drivers > 0}]
    dict set feat driver_is_clkbuf [expr {$num_clkbuf_drivers > 0}]

    # driver area
    dict set feat driver_inst_area $driver_area

    # sinks count
    set sink_cnt [llength $sink_xs]
    dict set feat sink_cnt $sink_cnt

    # spread stats for sinks
    set sx_mean [list_mean $sink_xs]
    set sy_mean [list_mean $sink_ys]
    dict set feat sink_x_mean $sx_mean
    dict set feat sink_y_mean $sy_mean
    dict set feat sink_x_std  [list_std $sink_xs $sx_mean]
    dict set feat sink_y_std  [list_std $sink_ys $sy_mean]
    dict set feat sink_min_x  [list_min $sink_xs]
    dict set feat sink_max_x  [list_max $sink_xs]
    dict set feat sink_min_y  [list_min $sink_ys]
    dict set feat sink_max_y  [list_max $sink_ys]

    # centroid distance to driver (Manhattan)
    if {$driver_xy ne "" && $sink_cnt > 0 && $sx_mean ne "" && $sy_mean ne ""} {
        lassign $driver_xy dx0 dy0
        dict set feat sink_centroid_dist_to_driver [expr {abs($sx_mean-$dx0)+abs($sy_mean-$dy0)}]
    } else {
        dict set feat sink_centroid_dist_to_driver ""
    }

    # distances driver->sink distribution
    if {$driver_xy ne "" && $sink_cnt > 0} {
        lassign $driver_xy dx0 dy0
        set sumd 0.0
        set maxd 0.0
        foreach {sx} $sink_xs { break } ;# keep Tcl happy

        # recompute using sink_xs/sink_ys pairwise
        for {set i 0} {$i < $sink_cnt} {incr i} {
            set sx [lindex $sink_xs $i]
            set sy [lindex $sink_ys $i]
            set d [expr {abs($sx-$dx0)+abs($sy-$dy0)}]
            lappend sink_distances $d
            set sumd [expr {$sumd + $d}]
            if {$d > $maxd} { set maxd $d }
        }

        dict set feat dist_drv_sink_sum  $sumd
        dict set feat dist_drv_sink_mean [expr {$sumd/double($sink_cnt)}]
        dict set feat dist_drv_sink_max  $maxd

        dict set feat sink_dist_p50 [list_percentile $sink_distances 50]
        dict set feat sink_dist_p90 [list_percentile $sink_distances 90]
        dict set feat sink_dist_p95 [list_percentile $sink_distances 95]
    } else {
        dict set feat dist_drv_sink_sum  ""
        dict set feat dist_drv_sink_mean ""
        dict set feat dist_drv_sink_max  ""
        dict set feat sink_dist_p50 ""
        dict set feat sink_dist_p90 ""
        dict set feat sink_dist_p95 ""
    }

    # quadrant histogram
    dict set feat sink_quadrant_q1 $q1
    dict set feat sink_quadrant_q2 $q2
    dict set feat sink_quadrant_q3 $q3
    dict set feat sink_quadrant_q4 $q4

    # sink areas stats
    dict set feat sink_area_sum  $sink_area_sum
    if {$sink_cnt > 0} {
        set a_mean [expr {$sink_area_sum/double($sink_cnt)}]
        dict set feat sink_area_mean $a_mean
        dict set feat sink_area_max  [list_max $sink_areas]
        dict set feat sink_area_std  [list_std $sink_areas $a_mean]
    } else {
        dict set feat sink_area_mean ""
        dict set feat sink_area_max  ""
        dict set feat sink_area_std  ""
    }
    dict set feat sink_area_ff_sum  $sink_area_ff_sum
    dict set feat sink_area_buf_sum $sink_area_buf_sum
    dict set feat sink_area_inv_sum $sink_area_inv_sum

    # name heuristics
    dict set feat is_clock_like [expr {[is_clock_like_name $net_name] ? 1 : 0}]
    dict set feat is_reset_like [expr {[is_reset_like_name $net_name] ? 1 : 0}]
    dict set feat is_enable_like [expr {[is_enable_like_name $net_name] ? 1 : 0}]
    dict set feat is_bus_bit [expr {[is_bus_bit_name $net_name] ? 1 : 0}]

    return $feat
}

# ---------------- main ----------------
# You must define:
#   set human_nets {...}
if {![info exists human_nets]} {
    puts "ERROR: define list 'human_nets' before sourcing this script."
    puts "Example: set human_nets [list net39 net157 usb_rst]"
    return
}

catch {unset all_keys}
array set all_keys {}

set feats_list {}

foreach n $human_nets {
    set f [extract_one_net_features $n $db_units_per_micron]
    lappend feats_list $f
    foreach k [dict keys $f] {
        set all_keys($k) 1
    }
}

set keys_sorted [lsort [array names all_keys]]
set header [list net_name status]
foreach k $keys_sorted {
    if {$k eq "net_name" || $k eq "status"} { continue }
    lappend header $k
}

set fo [open $out_csv w]
puts $fo [join $header ","]

foreach f $feats_list {
    set row {}
    foreach k $header {
        set v ""
        if {[dict exists $f $k]} { set v [dict get $f $k] }
        lappend row [csv_escape $v]
    }
    puts $fo [join $row ","]
}
close $fo

puts "Wrote: $out_csv"
