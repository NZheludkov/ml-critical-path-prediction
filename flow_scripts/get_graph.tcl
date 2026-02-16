# write_net_graph_edges.tcl
set out_dir "./graph"
exec mkdir -p $out_dir
set out_edges "$out_dir/edge_index.csv"

set fo [open $out_edges w]
puts $fo "src_net,dst_net"

# cache: map db-net-object -> human net name (fast)
array set NETNAME {}
proc net_hname {net_obj} {
    if {$net_obj eq "" || $net_obj eq "NULL"} { return "" }
    if {[info exists ::NETNAME($net_obj)]} { return $::NETNAME($net_obj) }
    set n [get_property -object_type net $net_obj name]
    set n [string trim $n]
    set ::NETNAME($net_obj) $n
    return $n
}

# Iterate instances (stdcells)
foreach inst [get_cells] {
    # Get pins of instance
    set pins [get_pins -of_objects $inst]
    if {[llength $pins] < 2} { continue }

    set in_nets {}
    set out_nets {}

    foreach p $pins {
        # direction property exists for pin objects in your SDC list
        set dir [get_property -object_type pin $p direction]
        set nets [get_nets -of_objects $p]
        if {[llength $nets] == 0} { continue }
        set nobj [lindex $nets 0]
        set nname [net_hname $nobj]
        if {$nname eq ""} { continue }

        # skip supplies/clocks optionally
        if {[regexp {^(VDD|VSS|VPWR|VGND)} $nname]} { continue }

        if {$dir eq "output"} {
            lappend out_nets $nname
        } elseif {$dir eq "input"} {
            lappend in_nets $nname
        } else {
            # inout/unknown -> treat as input (or skip)
            lappend in_nets $nname
        }
    }

    # Emit edges out->in
    foreach o $out_nets {
        foreach i $in_nets {
            if {$o eq $i} { continue }
            puts $fo "$o,$i"
        }
    }
}
close $fo
puts "Wrote edges: $out_edges"
