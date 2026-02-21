##START TIME
set start_time [exec date +%s]

# extract_endpoint_features_place_v2.tcl
# Endpoint features for ranking (place stage).
# Requires: sta::sta_to_db_inst and sta::sta_to_db_net available.

if {![info exists stage]} { set stage "features" }
if {![info exists db_units_per_micron]} { set db_units_per_micron 1000 }
if {![info exists endpoint_pin_regex]} { set endpoint_pin_regex {\/D$} }
if {![info exists neigh_radii]} { set neigh_radii {20 50 100} }
if {![info exists fanin_depth]} { set fanin_depth 0 }

if {![info exists stage]} { set stage "features" }
set out_dir "./$stage"
exec mkdir -p $out_dir
set out_csv "$out_dir/endpoint_features_place.csv"

if {![info exists endpoint_pin_regex]} { set endpoint_pin_regex {\/D$} }

if {![info exists db_units_per_micron]} { set db_units_per_micron 1000 }

# Neighborhood radii in microns (tune)
if {![info exists neigh_radii]} { set neigh_radii {20 50 100} }

# Optional: bounded fanin exploration depth (0 disables)
if {![info exists fanin_depth]} { set fanin_depth 0 } ;# set 2 or 3 to enable

# ---------------- helpers ----------------
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

proc pin_to_inst_name {pin_full_name} {
    set inst ""
    if {[regexp {^(.+)\/[^\/]+$} $pin_full_name -> inst]} { return $inst }
    return ""
}

proc get_inst_obj {inst_name} {
    set inst_obj [get_cells -hierarchical $inst_name]
    if {[llength $inst_obj] == 0} { return "" }
    return [lindex $inst_obj 0]
}

# Return {net_obj net_name}
proc pin_to_net {pin_obj} {
    set nl [get_nets -of_objects $pin_obj]
    if {[llength $nl] == 0} { return [list "" ""] }
    set net_obj [lindex $nl 0]
    set net_name [get_property -object_type net $net_obj name]
    return [list $net_obj $net_name]
}

# ODB net bbox + hpwl proxy + bbox area + net center
# Returns: xmin ymin xmax ymax dx dy hpwl area cx cy
proc odb_net_bbox_feats {net_obj dbu} {
    if {$net_obj eq ""} { return [list 0 0 0 0 0 0 0 0 0 0] }
    set dn [sta::sta_to_db_net $net_obj]
    if {$dn eq ""} { return [list 0 0 0 0 0 0 0 0 0 0] }

    set bb [$dn getTermBBox]
    if {$bb eq ""} { return [list 0 0 0 0 0 0 0 0 0 0] }

    set xmin [expr {[$bb xMin]/double($dbu)}]
    set ymin [expr {[$bb yMin]/double($dbu)}]
    set xmax [expr {[$bb xMax]/double($dbu)}]
    set ymax [expr {[$bb yMax]/double($dbu)}]
    set dx   [expr {$xmax-$xmin}]
    set dy   [expr {$ymax-$ymin}]
    set hpwl [expr {$dx+$dy}]
    set area [expr {$dx*$dy}]
    set cx   [expr {($xmin+$xmax)/2.0}]
    set cy   [expr {($ymin+$ymax)/2.0}]
    return [list $xmin $ymin $xmax $ymax $dx $dy $hpwl $area $cx $cy]
}

# ODB inst geom/status/orient + center
# Returns: x y w h cx cy orient status
proc odb_inst_geom {inst_obj dbu} {
    if {$inst_obj eq ""} { return [list 0 0 0 0 0 0 "" ""] }
    if {[catch { set di [sta::sta_to_db_inst $inst_obj] } err] || $di eq ""} {
        return [list 0 0 0 0 0 0 "" ""]
    }

    # bbox in DBU
    set bb [$di getBBox]
    set xmin [expr {[$bb xMin]/double($dbu)}]
    set ymin [expr {[$bb yMin]/double($dbu)}]
    set xmax [expr {[$bb xMax]/double($dbu)}]
    set ymax [expr {[$bb yMax]/double($dbu)}]
    set w [expr {$xmax-$xmin}]
    set h [expr {$ymax-$ymin}]
    set cx [expr {($xmin+$xmax)/2.0}]
    set cy [expr {($ymin+$ymax)/2.0}]

    set orient ""
    set status ""
    catch { set orient [$di getOrient] }
    catch { set status [$di getPlacementStatus] }
    return [list $xmin $ymin $w $h $cx $cy $orient $status]
}

# Liberty area for instance
proc inst_lib_area {inst_obj} {
    if {$inst_obj eq ""} { return 0.0 }
    set lc [get_property -object_type instance $inst_obj liberty_cell]
    if {$lc eq ""} { return 0.0 }
    set a [get_property -object_type liberty_cell $lc area]
    if {$a eq ""} { return 0.0 }
    return $a
}

# Count FF input/output/clk pins (cheap structural)
proc inst_pin_counts {inst_obj} {
    if {$inst_obj eq ""} { return [list 0 0 0 0] }
    set pins [get_pins -of_objects $inst_obj]
    set n_in 0
    set n_out 0
    set n_clk 0
    set n_inout 0
    foreach p $pins {
        set dir [get_property -object_type pin $p direction]
        set n [obj_full_name $p]
        if {[regexp {\/CLK$} $n]} { incr n_clk; continue }
        if {$dir eq "input"} { incr n_in }
        if {$dir eq "output"} { incr n_out }
        if {$dir eq "inout"} { incr n_inout }
    }
    return [list $n_in $n_out $n_clk $n_inout]
}

# Collect all data-input nets of FF instance excluding clock pins.
# Returns list of net STA objects (unique).
proc ff_data_input_nets {inst_obj} {
    array set seen {}
    set nets {}
    if {$inst_obj eq ""} { return $nets }
    set pins [get_pins -of_objects $inst_obj]
    foreach p $pins {
        set dir [get_property -object_type pin $p direction]
        if {$dir ne "input"} { continue }
        set pn [obj_full_name $p]
        if {[regexp {\/CLK$} $pn]} { continue }
        # include D, reset, scan, enable, etc.
        set nl [get_nets -of_objects $p]
        if {[llength $nl] == 0} { continue }
        set nobj [lindex $nl 0]
        if {$nobj eq "" || $nobj eq "NULL"} { continue }
        if {![info exists seen($nobj)]} {
            set seen($nobj) 1
            lappend nets $nobj
        }
    }
    return $nets
}

# Aggregate net bbox/hpwl/terms over a set of nets (STA net objects)
# Returns: cnt hpwl_sum hpwl_mean hpwl_max fanout_mean fanout_max term_mean term_max ports_cnt
proc agg_nets_basic {net_list dbu} {
    set cnt 0
    set hpwl_sum 0.0
    set hpwl_max 0.0
    set fan_sum 0.0
    set fan_max 0.0
    set term_sum 0.0
    set term_max 0.0
    set ports_cnt 0

    foreach net_obj $net_list {
        if {$net_obj eq ""} { continue }
        set nname [get_property -object_type net $net_obj name]
        if {$nname eq ""} { continue }
        if {[regexp {^(VDD|VSS|VPWR|VGND)} $nname]} { continue }

        incr cnt

        # hpwl proxy
        lassign [odb_net_bbox_feats $net_obj $dbu] xmin ymin xmax ymax dx dy hpwl area cx cy
        set hpwl_sum [expr {$hpwl_sum + $hpwl}]
        if {$hpwl > $hpwl_max} { set hpwl_max $hpwl }

        # terms & fanout proxy
        set dn [sta::sta_to_db_net $net_obj]
        set termCount 0
        if {$dn ne ""} { set termCount [$dn getTermCount] }
        set term_sum [expr {$term_sum + $termCount}]
        if {$termCount > $term_max} { set term_max $termCount }

        set fanout [expr {max(0, $termCount - 1)}]
        set fan_sum [expr {$fan_sum + $fanout}]
        if {$fanout > $fan_max} { set fan_max $fanout }

        if {[get_ports $nname] ne ""} { incr ports_cnt }
    }

    if {$cnt > 0} {
        set hpwl_mean [expr {$hpwl_sum / double($cnt)}]
        set fan_mean  [expr {$fan_sum / double($cnt)}]
        set term_mean [expr {$term_sum / double($cnt)}]
    } else {
        set hpwl_mean 0.0
        set fan_mean 0.0
        set term_mean 0.0
    }

    return [list $cnt $hpwl_sum $hpwl_mean $hpwl_max $fan_mean $fan_max $term_mean $term_max $ports_cnt]
}

# Build spatial grid for fast neighbor queries.
# centers: list of {cx cy}
# cell_size: microns
# Returns dict-like array name GRID where GRID("ix,iy") = list of indices
proc build_grid {centers cell_size} {
    array set GRID {}
    set i 0
    foreach xy $centers {
        set x [lindex $xy 0]
        set y [lindex $xy 1]
        set ix [expr {int(floor($x / double($cell_size)))}]
        set iy [expr {int(floor($y / double($cell_size)))}]
        set key "$ix,$iy"
        if {[info exists GRID($key)]} {
            lappend GRID($key) $i
        } else {
            set GRID($key) [list $i]
        }
        incr i
    }
    return [array get GRID]
}

# Count neighbors within multiple radii using grid.
# centers: list of {cx cy}
# grid_kv: result of build_grid (array get GRID)
# cell_size: microns
# idx: index of current point in centers
# radii: list of radii in microns
# Returns list of counts in same order as radii.
proc count_neighbors_grid {centers grid_kv cell_size idx radii} {
    array set GRID $grid_kv

    set xy [lindex $centers $idx]
    set cx [lindex $xy 0]
    set cy [lindex $xy 1]

    # current cell
    set cix [expr {int(floor($cx / double($cell_size)))}]
    set ciy [expr {int(floor($cy / double($cell_size)))}]

    # prepare counts
    array set cnt {}
    foreach r $radii { set cnt($r) 0 }

    # We need to search neighbor grid cells that could contain points within max_r
    set max_r 0
    foreach r $radii { if {$r > $max_r} { set max_r $r } }

    # How many cells to expand around current cell
    set k [expr {int(ceil($max_r / double($cell_size)))}]

    # check candidate points
    foreach dx [range -$k $k] {
        foreach dy [range -$k $k] {
            set key "[expr {$cix+$dx}],[expr {$ciy+$dy}]"
            if {![info exists GRID($key)]} { continue }
            foreach j $GRID($key) {
                if {$j == $idx} { continue }
                set xy2 [lindex $centers $j]
                set x2 [lindex $xy2 0]
                set y2 [lindex $xy2 1]
                set ddx [expr {$x2-$cx}]
                set ddy [expr {$y2-$cy}]
                set d2 [expr {$ddx*$ddx + $ddy*$ddy}]
                foreach r $radii {
                    if {$d2 <= $r*$r} { incr cnt($r) }
                }
            }
        }
    }

    set out {}
    foreach r $radii { lappend out $cnt($r) }
    return $out
}

# Tcl helper: generate integer range [a..b]
proc range {a b} {
    set out {}
    if {$a <= $b} {
        for {set i $a} {$i <= $b} {incr i} { lappend out $i }
    } else {
        for {set i $a} {$i >= $b} {incr i -1} { lappend out $i }
    }
    return $out
}


# Optional: bounded fanin exploration from a net (counts cell types within K)
# NOTE: lightweight heuristic; does not require STA timing arcs.
proc fanin_counts {start_net depth} {
    if {$depth <= 0 || $start_net eq ""} { return [list 0 0 0 0 0] }
    array set seen_net {}
    array set seen_cell {}
    set q [list [list $start_net 0]]

    set n_cells 0
    set n_buf 0
    set n_inv 0
    set n_ff 0
    set n_nets 0

    while {[llength $q] > 0} {
        set item [lindex $q 0]
        set q [lrange $q 1 end]
        set net [lindex $item 0]
        set d   [lindex $item 1]
        if {[info exists seen_net($net)]} { continue }
        set seen_net($net) 1
        incr n_nets

        if {$d >= $depth} { continue }

        # drivers of this net are output pins; approximate by scanning iterms on net and finding output pins
        set dn [sta::sta_to_db_net $net]
        if {$dn eq ""} { continue }
        foreach it [$dn getITerms] {
            # it is dbITerm; get inst and mterm
            set inst [$it getInst]
            if {$inst eq ""} { continue }
            set iname [$inst getName]
            if {[info exists seen_cell($iname)]} { continue }

            # classify inst via liberty_cell if possible
            set inst_obj [get_cells -hierarchical $iname]
            if {[llength $inst_obj] == 0} { continue }
            set inst_obj [lindex $inst_obj 0]

            set lc [get_property -object_type instance $inst_obj liberty_cell]
            set ref [get_property -object_type instance $inst_obj ref_name]

            set is_buf 0
            set is_inv 0
            set is_ff  0
            if {$lc ne ""} {
                if {[get_property -object_type liberty_cell $lc is_buffer] eq "1"} { set is_buf 1 }
                if {[get_property -object_type liberty_cell $lc is_inverter] eq "1"} { set is_inv 1 }
            }
            # crude FF detect by name
            if {[regexp {dfxt|dff|sdff|latch} $ref]} { set is_ff 1 }

            set seen_cell($iname) 1
            incr n_cells
            if {$is_buf} { incr n_buf }
            if {$is_inv} { incr n_inv }
            if {$is_ff}  { incr n_ff }

            # enqueue input nets of this cell (fanin direction)
            set pins [get_pins -of_objects $inst_obj]
            foreach p $pins {
                set dir [get_property -object_type pin $p direction]
                if {$dir ne "input"} { continue }
                set nl [get_nets -of_objects $p]
                if {[llength $nl] == 0} { continue }
                set nin [lindex $nl 0]
                if {$nin eq ""} { continue }
                lappend q [list $nin [expr {$d+1}]]
            }
        }
    }

    return [list $n_cells $n_buf $n_inv $n_ff $n_nets]
}

# ---------------- main ----------------
set eps [collect_endpoint_pins $endpoint_pin_regex]
puts "INFO: endpoints_found=[llength $eps]"

# Precompute FF centers for neighborhood counts
set centers {}

# Ensure ep2center_idx is an ARRAY (it may exist as a scalar from earlier scripts)
catch { unset ep2center_idx }
array set ep2center_idx {}

set i 0
foreach ep $eps {
    set ep_name [obj_full_name $ep]
    set inst_name [pin_to_inst_name $ep_name]
    set inst_obj [get_inst_obj $inst_name]
    lassign [odb_inst_geom $inst_obj $db_units_per_micron] ix iy iw ih cx cy orient status

    lappend centers [list $cx $cy]
    set ep2center_idx($ep_name) $i
    incr i
}

# ---- Build spatial grid ONCE ----
set max_r 0
foreach r $neigh_radii { if {$r > $max_r} { set max_r $r } }
set grid_cell_size $max_r
set grid_kv [build_grid $centers $grid_cell_size]
puts "INFO: neighbor grid built once (cell_size=${grid_cell_size}um)"

# CSV header
set fo [open $out_csv w]
set header "endpoint,instance,worst_pin_regex,ff_area,ff_ref,ff_x,ff_y,ff_w,ff_h,ff_cx,ff_cy,ff_orient,ff_status,ff_in_pins,ff_out_pins,ff_clk_pins,ff_inout_pins"
# D-net
append header ",D_net,D_is_port,D_dx,D_dy,D_hpwl,D_bbox_area,D_termCount,D_iterms,D_bterms,D_fanout_proxy,D_net_center_dx,D_net_center_dy"
# Aggregates over all data input nets
append header ",in_nets_cnt,in_hpwl_sum,in_hpwl_mean,in_hpwl_max,in_fanout_mean,in_fanout_max,in_term_mean,in_term_max,in_ports_cnt"
# Neighborhood
foreach r $neigh_radii { append header ",ff_neighbors_r${r}" }
# Optional fanin counts
if {$fanin_depth > 0} { append header ",fanin_cells_k${fanin_depth},fanin_buf_k${fanin_depth},fanin_inv_k${fanin_depth},fanin_ff_k${fanin_depth},fanin_nets_k${fanin_depth}" }

puts $fo $header

foreach ep $eps {
    set ep_name [obj_full_name $ep]
    set inst_name [pin_to_inst_name $ep_name]
    set inst_obj [get_inst_obj $inst_name]

    # inst feats
    set ff_area [inst_lib_area $inst_obj]
    set ff_ref  [get_property -object_type instance $inst_obj ref_name]
    lassign [odb_inst_geom $inst_obj $db_units_per_micron] ix iy iw ih cx cy orient status
    lassign [inst_pin_counts $inst_obj] ff_in ff_out ff_clk ff_inout

    # ---- neighborhood counts (fast) ----
    set neigh_counts {}
    if {[info exists ep2center_idx($ep_name)]} {
        set idx_center $ep2center_idx($ep_name)
        set neigh_counts [count_neighbors_grid \
            $centers $grid_kv $grid_cell_size \
            $idx_center $neigh_radii]
    } else {
        # safety fallback
        foreach r $neigh_radii { lappend neigh_counts 0 }
    }

    # D net feats
    lassign [pin_to_net $ep] D_net_obj D_net_name
    set D_is_port 0
    if {$D_net_name ne "" && [get_ports $D_net_name] ne ""} { set D_is_port 1 }

    set D_termCount 0
    set D_iterms 0
    set D_bterms 0
    set D_fanout 0
    set D_dx 0; set D_dy 0; set D_hpwl 0; set D_area 0; set D_ncx 0; set D_ncy 0
    if {$D_net_obj ne ""} {
        set dn [sta::sta_to_db_net $D_net_obj]
        if {$dn ne ""} {
            set D_termCount [$dn getTermCount]
            set D_iterms [llength [$dn getITerms]]
            set D_bterms [llength [$dn getBTerms]]
            set D_fanout [expr {max(0, $D_termCount - 1)}]
        }
        lassign [odb_net_bbox_feats $D_net_obj $db_units_per_micron] xmin ymin xmax ymax D_dx D_dy D_hpwl D_area D_ncx D_ncy
    }
    set D_net_center_dx [expr {$D_ncx - $cx}]
    set D_net_center_dy [expr {$D_ncy - $cy}]

    # Aggregate over all data input nets (including D, reset, scan, enable; excluding CLK)
    set in_nets [ff_data_input_nets $inst_obj]
    lassign [agg_nets_basic $in_nets $db_units_per_micron] in_cnt in_hpwl_sum in_hpwl_mean in_hpwl_max in_fan_mean in_fan_max in_term_mean in_term_max in_ports_cnt

    # Optional fanin counts from D net
    set fanin_cells 0; set fanin_buf 0; set fanin_inv 0; set fanin_ff 0; set fanin_nets 0
    if {$fanin_depth > 0 && $D_net_obj ne ""} {
        lassign [fanin_counts $D_net_obj $fanin_depth] fanin_cells fanin_buf fanin_inv fanin_ff fanin_nets
    }

    # Compose row
    set row "\"$ep_name\",\"$inst_name\",\"$endpoint_pin_regex\",$ff_area,\"$ff_ref\",$ix,$iy,$iw,$ih,$cx,$cy,\"$orient\",\"$status\",$ff_in,$ff_out,$ff_clk,$ff_inout"
    append row ",\"$D_net_name\",$D_is_port,$D_dx,$D_dy,$D_hpwl,$D_area,$D_termCount,$D_iterms,$D_bterms,$D_fanout,$D_net_center_dx,$D_net_center_dy"
    append row ",$in_cnt,$in_hpwl_sum,$in_hpwl_mean,$in_hpwl_max,$in_fan_mean,$in_fan_max,$in_term_mean,$in_term_max,$in_ports_cnt"

    # neighborhood cols
    set j 0
    foreach r $neigh_radii {
        append row ",[lindex $neigh_counts $j]"
        incr j
    }

    if {$fanin_depth > 0} {
        append row ",$fanin_cells,$fanin_buf,$fanin_inv,$fanin_ff,$fanin_nets"
    }

    puts $fo $row
}
close $fo
puts "Wrote: $out_csv"


##END TIME
set end_time [exec date +%s]
set extract_feats_place_time [expr $end_time - $start_time]