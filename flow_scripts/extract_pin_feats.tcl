##PROCS
proc tcl::mathfunc::roundto {value sigfigs} {
set pow [expr ($sigfigs-1)-floor(log10($value))]
expr {round(10**$pow*$value)/10.0**$pow}
}

#corner name
set corner [sta::corners]

##db_units_per_micron
set db [::ord::get_db]
set block [[$db getChips] getBlock]
set db_units_per_micron [$block getDbUnitsPerMicron]

set block_llx [expr [[$block getBBox] xMin] / $db_units_per_micron]
set block_lly [expr [[$block getBBox] yMin] / $db_units_per_micron]
set block_urx [expr [[$block getBBox] xMax] / $db_units_per_micron]
set block_ury [expr [[$block getBBox] yMax] / $db_units_per_micron]

##block area
set block_area [expr $block_urx * $block_ury]
 
##data flor wireload model
set res_eq "0.00023" ;#kOm
set cap_eq "0.00018" ;#pf
set max_output_load 0.1
set min_output_load 0.1
##choose wireload model based on block area

if {($block_area <= 960) && (($block_area >= 0))} {
set slope 9.35
}

if {($block_area <= 3840) && (($block_area >= 960))} {
set slope 14.77
}

if {($block_area <= 7680) && (($block_area >= 3840))} {
set slope 18.57
}

if {($block_area <= 14080) && (($block_area >= 7680))} {
set slope 22.85
}

if {($block_area <= 48000) && (($block_area >= 14080))} {
set slope 34.0
}

if {($block_area <= 192000) && (($block_area >= 48000))} {
set slope 53.73
}

if {($block_area <= 576000) && (($block_area >= 192000))} {
set slope 77.21
}

if {($block_area <= 768000) && (($block_area >= 576000))} {
set slope 84.90
}

if {($block_area <= 960000) && (($block_area >= 768000))} {
set slope 91.39
}

if {($block_area <= 1920000) && (($block_area >= 960000))} {
set slope 114.88
}

if {$block_area >= 1920000} {
set slope 131.32 
}


##endpoints list
set endpoints_list [sta::endpoints]

##########PIN NODES

#1x is primary I/O pin (1) or not (0) +
#1x is fanin (0) or fanout (1) +
#1x fanout for fanin pins N, if pin fanout => N = 0
#4x relative to the top/left/right/bottom of die area +
#2x capacitance information (EL) in cell library +
#1x is timing endpoint (i.e. has constraint) (1) or not (0) +
#4x arrival time annotations (EL/RF) +
#4x required arrival time annotations (EL/RF) +
#4x slew annotations (EL/RF) +
#1x net_delay_wireload
#2x net delay annotations (EL) for fanin pins +

set node_id 0

set feats_name_list "\
node_id
is_port
is_fanin
N_fanout
bottom
left
right
top
max_pin_capacitence
min_pin_capacitence
is_endpoint
min_rise_arrival
max_rise_arrival
min_fall_arrival
max_fall_arrival
min_rise_required
max_rise_required
min_fall_required
max_fall_required
min_rise_slew
max_rise_slew
min_fall_slew
max_fall_slew
net_delay_wireload
max_net_delay
min_net_delay
"

foreach pin [get_pins * -filter "direction==input || direction==output"] {

	set full_pin_name [get_full_name $pin]
	
	##node index
	dict set dict_nodes $full_pin_name "node_id" $node_id
	incr node_id
	
	#is primary I/O pin (1) or not (0)
	dict set dict_nodes $full_pin_name "is_port" "0.0"
	
	#1x is fanin (0) or fanout (1)
	if { ([$pin is_load] eq "1") && ([$pin is_driver] eq "0")} {
	dict set dict_nodes $full_pin_name "is_fanin" "1.0"
	}
	
	if { ([$pin is_load] eq "0") && ([$pin is_driver] eq "1")} {
	dict set dict_nodes $full_pin_name "is_fanin" "0.0"
	}
	
	#1x fanout for fanin pins N, if pin fanout => N = 0
	if { ([$pin is_load] eq "0") && ([$pin is_driver] eq "1")} {
	dict set dict_nodes $full_pin_name "N_fanout" [expr [llength [get_fanout -from $pin -pin_levels 1]] -1]
	} else {
	dict set dict_nodes $full_pin_name "N_fanout" "0.0"
	}
	
	#4x relative to the top/left/right/bottom of die area
	set bottom [expr ([lindex [[sta::sta_to_db_pin $pin] getAvgXY] 2] / $db_units_per_micron) - $block_lly]
	set left   [expr ([lindex [[sta::sta_to_db_pin $pin] getAvgXY] 1] / $db_units_per_micron) - $block_llx]
	set right  [expr - ([lindex [[sta::sta_to_db_pin $pin] getAvgXY] 1] / $db_units_per_micron) + $block_urx]
	set top    [expr -([lindex [[sta::sta_to_db_pin $pin] getAvgXY] 2] / $db_units_per_micron) + $block_ury]
	
	dict set dict_nodes $full_pin_name "bottom" $bottom
	dict set dict_nodes $full_pin_name "left" $left
	dict set dict_nodes $full_pin_name "right" $right
	dict set dict_nodes $full_pin_name "top" $top
	
	#2x capacitance information (EL) in cell library
	set max_pin_capacitence [expr ([[$pin liberty_port] capacitance $corner max] / 1e-12)]
	set min_pin_capacitence [expr ([[$pin liberty_port] capacitance $corner min] / 1e-12)]
	
	if {$max_pin_capacitence ne "0.0"} {
	set max_pin_capacitence [expr roundto($max_pin_capacitence,3)]
	}
	
	if {$min_pin_capacitence ne "0.0"} {
	set min_pin_capacitence [expr roundto($min_pin_capacitence,3)]
	}

	dict set dict_nodes $full_pin_name "max_pin_capacitence" $max_pin_capacitence
	dict set dict_nodes $full_pin_name "min_pin_capacitence" $min_pin_capacitence
	
	#1x is timing endpoint (i.e. has constraint) (1) or not (0)
	if {[lsearch $endpoints_list $pin] ne "-1"} {
	dict set dict_nodes $full_pin_name "is_endpoint" "1.0"
	} else {
	dict set dict_nodes $full_pin_name "is_endpoint" "0.0"
	}
	
	#4x arrival time annotations (EL/RF)
	if { [[$pin vertices] is_clock] ne "1"} {
	set min_rise_arrival [lindex [[$pin vertices] arrivals_clk_delays rise [get_clocks *] rise 3] 0]
	set max_rise_arrival [lindex [[$pin vertices] arrivals_clk_delays rise [get_clocks *] rise 3] 1]
	set min_fall_arrival [lindex [[$pin vertices] arrivals_clk_delays fall [get_clocks *] rise 3] 0]
	set max_fall_arrival [lindex [[$pin vertices] arrivals_clk_delays fall [get_clocks *] rise 3] 1]
	} else {
	set min_rise_arrival [lindex [[$pin vertices] arrivals_clk_delays rise [get_clocks *] rise 3] 0]
	set max_rise_arrival [lindex [[$pin vertices] arrivals_clk_delays rise [get_clocks *] rise 3] 1]
	set min_fall_arrival [lindex [[$pin vertices] arrivals_clk_delays fall [get_clocks *] fall 3] 0]
	set max_fall_arrival [lindex [[$pin vertices] arrivals_clk_delays fall [get_clocks *] fall 3] 1]
	}
	
	dict set dict_nodes $full_pin_name "min_rise_arrival" $min_rise_arrival
	dict set dict_nodes $full_pin_name "max_rise_arrival" $max_rise_arrival
	dict set dict_nodes $full_pin_name "min_fall_arrival" $min_fall_arrival
	dict set dict_nodes $full_pin_name "max_fall_arrival" $max_fall_arrival
	
	#4x required arrival time annotations (EL/RF)
	if { [[$pin vertices] is_clock] ne "1"} {
	set min_rise_required [lindex [[$pin vertices] requireds_clk_delays rise [get_clocks *] rise 3] 0]
	set max_rise_required [lindex [[$pin vertices] requireds_clk_delays rise [get_clocks *] rise 3] 1]
	set min_fall_required [lindex [[$pin vertices] requireds_clk_delays fall [get_clocks *] rise 3] 0]
	set max_fall_required [lindex [[$pin vertices] requireds_clk_delays fall [get_clocks *] rise 3] 1]
	} else {
	set min_rise_required [lindex [[$pin vertices] requireds_clk_delays rise [get_clocks *] rise 3] 0]
	set max_rise_required [lindex [[$pin vertices] requireds_clk_delays rise [get_clocks *] rise 3] 1]
	set min_fall_required 0.0
	set max_fall_required 0.0
	}
	
	dict set dict_nodes $full_pin_name "min_rise_required" $min_rise_required
	dict set dict_nodes $full_pin_name "max_rise_required" $max_rise_required
	dict set dict_nodes $full_pin_name "min_fall_required" $min_fall_required
	dict set dict_nodes $full_pin_name "max_fall_required" $max_fall_required
	
	#4x slew annotations (EL/RF)
	if {[expr ([[$pin vertices] slew rise min] / 1e-9)] eq "0.0"} {
	set min_rise_slew [expr ([[$pin vertices] slew rise min] / 1e-9)]
	set max_rise_slew [expr ([[$pin vertices] slew rise max] / 1e-9)]
	set min_fall_slew [expr ([[$pin vertices] slew fall min] / 1e-9)]
	set max_fall_slew [expr ([[$pin vertices] slew fall max] / 1e-9)]	
	} else {
	set min_rise_slew [expr roundto(([[$pin vertices] slew rise min] / 1e-9),3)]
	set max_rise_slew [expr roundto(([[$pin vertices] slew rise max] / 1e-9),3)]
	set min_fall_slew [expr roundto(([[$pin vertices] slew fall min] / 1e-9),3)]
	set max_fall_slew [expr roundto(([[$pin vertices] slew fall max] / 1e-9),3)]
	}
	
	dict set dict_nodes $full_pin_name "min_rise_slew" $min_rise_slew
	dict set dict_nodes $full_pin_name "max_rise_slew" $max_rise_slew
	dict set dict_nodes $full_pin_name "min_fall_slew" $min_fall_slew
	dict set dict_nodes $full_pin_name "max_fall_slew" $max_fall_slew
	
	#1x net_delay_wireload
	if { ([$pin is_load] eq "1") && ([$pin is_driver] eq "0")} {
	set N [expr [[sta::sta_to_db_net [$pin net]] getTermCount] - 1]
	if {$N ne 0} {
	set wire_capacitence [expr ($slope + ($N-1)*$slope)*$cap_eq] ;#pf
	set wire_resistance  [expr 1e3 * (($slope + ($N-1)*$slope)*$res_eq)] ;#kOm
		if { [expr ($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_pin_capacitence)] eq "0.0"} {
		dict set dict_nodes $full_pin_name "net_delay_wireload" 0.0
		} else {
		dict set dict_nodes $full_pin_name "net_delay_wireload" [expr roundto(($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_pin_capacitence),3)]
		}
	} else {
	dict set dict_nodes $full_pin_name "net_delay_wireload" 0.0
	}
	} else {
	dict set dict_nodes $full_pin_name "net_delay_wireload" 0.0
	}
	
	#2x net delay annotations (EL) for fanin pin
	if { ([$pin is_load] eq "0") && ([$pin is_driver] eq "1")} {
	dict set dict_nodes $full_pin_name "max_net_delay" "0.0"
	dict set dict_nodes $full_pin_name "min_net_delay" "0.0"
	}
	
	if { ([$pin is_load] eq "1") && ([$pin is_driver] eq "0")} {
	set wire_capacitence [expr [[$pin net] wire_capacitance $corner max] / 1e-12]
	set wire_resistance [[sta::sta_to_db_net [$pin net]] getTotalResistance]
	set N [expr [[sta::sta_to_db_net [$pin net]] getTermCount] - 1]
	if {$N ne "0"} {
		if { [expr ($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_pin_capacitence)] eq "0.0"} {
		set max_net_delay 0.0
		set mim_net_delay 0.0
		} else {
		set max_net_delay [expr roundto(($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_pin_capacitence),3)]
		set min_net_delay [expr roundto(($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $min_pin_capacitence),3)]
		}
	dict set dict_nodes $full_pin_name "max_net_delay" $max_net_delay
	dict set dict_nodes $full_pin_name "min_net_delay" $min_net_delay
	} else {
	dict set dict_nodes $full_pin_name "max_net_delay" 0.0
	dict set dict_nodes $full_pin_name "min_net_delay" 0.0
	}
	}

}





##########PORT NODES

#1x is primary I/O pin (1) or not (0) +
#1x is fanin (0) or fanout (1) +
#1x fanout for fanin pins N, if pin fanout => N = 0
#4x relative to the top/left/right/bottom of die area  +
#2x capacitance information (EL) in cell library +
#1x is timing endpoint (i.e. has constraint) (1) or not (0) +
#4x arrival time annotations (EL/RF) +
#4x required arrival time annotations (EL/RF)  +
#4x slew annotations (EL/RF) +
#1x net_delay_wireload
#2x net delay annotations (EL) for fanin pins  +


foreach pin [get_ports * -filter "direction==input || direction==output"] {

	set full_pin_name [get_full_name $pin]
	
	##node index
	dict set dict_nodes $full_pin_name "node_id" $node_id
	incr node_id

	#is primary I/O pin (1) or not (0)
	dict set dict_nodes $full_pin_name "is_port" "1.0"

	#1x is fanin (0) or fanout (1)
	if { [get_property -object_type "port" $pin "direction"] eq "input"} {
	dict set dict_nodes $full_pin_name "is_fanin" "0.0"
	}
	
	if { [get_property -object_type "port" $pin "direction"] eq "output"} {
	dict set dict_nodes $full_pin_name "is_fanin" "1.0"
	}
	
	#1x fanout for fanin pins N, if pin fanout => N = 0
	if { [get_property -object_type "port" $pin "direction"] eq "input"} {
	dict set dict_nodes $full_pin_name "N_fanout" [expr [llength [get_fanout -from $pin -pin_levels 1]] -1]
	} else {
	dict set dict_nodes $full_pin_name "N_fanout" "0.0"
	}
	
	#4x relative to the top/left/right/bottom of die area
	set bottom [expr (( [[[sta::sta_to_db_port $pin] getBBox] yCenter]  / $db_units_per_micron) - $block_lly)]
	set left   [expr ([[[sta::sta_to_db_port $pin] getBBox] xCenter] / $db_units_per_micron) - $block_llx]
	set right  [expr - ([[[sta::sta_to_db_port $pin] getBBox] xCenter] / $db_units_per_micron) + $block_urx]
	set top    [expr -([[[sta::sta_to_db_port $pin] getBBox] yCenter] / $db_units_per_micron) + $block_ury]

	dict set dict_nodes $full_pin_name "bottom" $bottom
	dict set dict_nodes $full_pin_name "left" $left
	dict set dict_nodes $full_pin_name "right" $right
	dict set dict_nodes $full_pin_name "top" $top
	
	#2x capacitance information (EL) in cell library
	if { [get_property -object_type "port" $pin "direction"] eq "input"} {
	dict set dict_nodes $full_pin_name "max_pin_capacitence" 0.0
	dict set dict_nodes $full_pin_name "min_pin_capacitence" 0.0
	}
	
	if { [get_property -object_type "port" $pin "direction"] eq "output"} {
	dict set dict_nodes $full_pin_name "max_pin_capacitence" 0.1
	dict set dict_nodes $full_pin_name "min_pin_capacitence" 0.1
	}
	
	#1x is timing endpoint (i.e. has constraint) (1) or not (0) 
	if {[lsearch $endpoints_list $pin] ne "-1"} {
	dict set dict_nodes $full_pin_name "is_endpoint" "1.0"
	} else {
	dict set dict_nodes $full_pin_name "is_endpoint" "0.0"
	}
	
	#4x arrival time annotations (EL/RF)
	set min_rise_arrival [lindex [[[sta::get_port_pin $pin] vertices] arrivals_clk_delays rise [get_clocks *] rise 3] 0]
	set max_rise_arrival [lindex [[[sta::get_port_pin $pin] vertices] arrivals_clk_delays rise [get_clocks *] rise 3] 1]
	set min_fall_arrival [lindex [[[sta::get_port_pin $pin] vertices] arrivals_clk_delays fall [get_clocks *] rise 3] 0]
	set max_fall_arrival [lindex [[[sta::get_port_pin $pin] vertices] arrivals_clk_delays fall [get_clocks *] rise 3] 1]
	
	dict set dict_nodes $full_pin_name "min_rise_arrival" $min_rise_arrival
	dict set dict_nodes $full_pin_name "max_rise_arrival" $max_rise_arrival
	dict set dict_nodes $full_pin_name "min_fall_arrival" $min_fall_arrival
	dict set dict_nodes $full_pin_name "max_fall_arrival" $max_fall_arrival
	
	#4x required arrival time annotations (EL/RF) 
	set min_rise_required [lindex [[[sta::get_port_pin $pin] vertices] requireds_clk_delays rise [get_clocks *] rise 3] 0]
	set max_rise_required [lindex [[[sta::get_port_pin $pin] vertices] requireds_clk_delays rise [get_clocks *] rise 3] 1]
	set min_fall_required [lindex [[[sta::get_port_pin $pin] vertices] requireds_clk_delays fall [get_clocks *] rise 3] 0]
	set max_fall_required [lindex [[[sta::get_port_pin $pin] vertices] requireds_clk_delays fall [get_clocks *] rise 3] 1]
	
	dict set dict_nodes $full_pin_name "min_rise_required" $min_rise_required
	dict set dict_nodes $full_pin_name "max_rise_required" $max_rise_required
	dict set dict_nodes $full_pin_name "min_fall_required" $min_fall_required
	dict set dict_nodes $full_pin_name "max_fall_required" $max_fall_required
	
	#4x slew annotations (EL/RF)
	if { ([[[sta::get_port_pin $pin] vertices] is_clock] ne "1") && ([[sta::get_port_pin $pin]  is_driver] ne "1")} {
	
		if { [expr ([[[sta::get_port_pin $pin] vertices] slew rise min] / 1e-9)] eq "0.0"} {
			set min_rise_slew [expr ([[[sta::get_port_pin $pin] vertices] slew rise min] / 1e-9)]
			set max_rise_slew [expr ([[[sta::get_port_pin $pin] vertices] slew rise max] / 1e-9)]
			set min_fall_slew [expr ([[[sta::get_port_pin $pin] vertices] slew fall min] / 1e-9)]
			set max_fall_slew [expr ([[[sta::get_port_pin $pin] vertices] slew fall max] / 1e-9)]
		} else {
			set min_rise_slew [expr roundto(([[[sta::get_port_pin $pin] vertices] slew rise min] / 1e-9),3)]
			set max_rise_slew [expr roundto(([[[sta::get_port_pin $pin] vertices] slew rise max] / 1e-9),3)]
			set min_fall_slew [expr roundto(([[[sta::get_port_pin $pin] vertices] slew fall min] / 1e-9),3)]
			set max_fall_slew [expr roundto(([[[sta::get_port_pin $pin] vertices] slew fall max] / 1e-9),3)]
		}
	} else {
	set min_rise_slew [expr ([[[sta::get_port_pin $pin] vertices] slew rise min] / 1e-9)]
	set max_rise_slew [expr ([[[sta::get_port_pin $pin] vertices] slew rise max] / 1e-9)]
	set min_fall_slew [expr ([[[sta::get_port_pin $pin] vertices] slew fall min] / 1e-9)]
	set max_fall_slew [expr ([[[sta::get_port_pin $pin] vertices] slew fall max] / 1e-9)]
	}
	
	dict set dict_nodes $full_pin_name "min_rise_slew" $min_rise_slew
	dict set dict_nodes $full_pin_name "max_rise_slew" $max_rise_slew
	dict set dict_nodes $full_pin_name "min_fall_slew" $min_fall_slew
	dict set dict_nodes $full_pin_name "max_fall_slew" $max_fall_slew
	
	#1x net_delay_wireload
	if { ([[sta::get_port_pin $pin] is_load] eq "1") && ([[sta::get_port_pin $pin] is_driver] eq "0")} {
	set N [expr [[sta::sta_to_db_net [get_nets [[[sta::sta_to_db_port $pin] getNet] getName]]] getTermCount] -1]
	if {$N ne 0} {
	set wire_capacitence [expr ($slope + ($N-1)*$slope)*$cap_eq] ;#pf
	set wire_resistance  [expr 1e3 * (($slope + ($N-1)*$slope)*$res_eq)] ;#kOm
		if { [expr ($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_output_load)] eq "0.0"} {
		dict set dict_nodes $full_pin_name "net_delay_wireload" 0.0
		} else {
		dict set dict_nodes $full_pin_name "net_delay_wireload" [expr roundto(($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_output_load),3)]
		}
	} else {
	dict set dict_nodes $full_pin_name "net_delay_wireload" 0.0
	}
	} else {
	dict set dict_nodes $full_pin_name "net_delay_wireload" 0.0
	}
	
	#2x net delay annotations (EL) for fanin pins 
	if { ([[sta::get_port_pin $pin] is_load] eq "1") && ([[sta::get_port_pin $pin] is_driver] eq "0")} {
	set wire_capacitence [expr [[get_nets [[[sta::sta_to_db_port $pin] getNet] getName]] wire_capacitance $corner max] / 1e-12]
	set wire_resistance [[sta::sta_to_db_net [get_nets [[[sta::sta_to_db_port $pin] getNet] getName]]] getTotalResistance]
	set N [expr [[sta::sta_to_db_net [get_nets [[[sta::sta_to_db_port $pin] getNet] getName]]] getTermCount] - 1]
	if {$N ne 0} {
		if { [expr ($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_pin_capacitence)] eq "0.0"} {
			set max_net_delay [expr ($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_output_load)]
			set min_net_delay [expr ($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $min_output_load)]
		} else {
			set max_net_delay [expr roundto(($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $max_output_load),3)]
			set min_net_delay [expr roundto(($wire_resistance / $N) * (($wire_capacitence / (2 * $N)) + $min_output_load),3)]
		}
	dict set dict_nodes $full_pin_name "max_net_delay" $max_net_delay
	dict set dict_nodes $full_pin_name "min_net_delay" $min_net_delay
	} else {
	dict set dict_nodes $full_pin_name "max_net_delay" 0.0
	dict set dict_nodes $full_pin_name "min_net_delay" 0.0
	}
	} else {
	dict set dict_nodes $full_pin_name "max_net_delay" 0.0
	dict set dict_nodes $full_pin_name "min_net_delay" 0.0
	}
}

##WRITE TO CSV FILE
set file [open ./node_features.csv w+]

puts -nonewline $file "node;"

foreach name $feats_name_list {
puts -nonewline $file "$name;"
}

puts $file ""

foreach id [dict keys $dict_nodes] {

puts  -nonewline $file "$id;"

	foreach name $feats_name_list {
	puts -nonewline $file "[dict get $dict_nodes $id $name];"
	}
	
	puts $file ""
	
}

close $file


set file [open ./set_node_attr.txt w+]

	foreach id [dict keys $dict_nodes] {
	
	
		foreach feat $feats_name_list {
		puts $file "nx.set_node_attributes(G, { '${id}': [dict get $dict_nodes $id $feat]}, '$feat')"
		}
		
	}



close $file



##CHANGE INF TO 0.0
exec sed -i -e "s/INF/0.0/g" ./node_features.csv

##CHANGE INF TO 0.0
exec sed -i -e "s/INF/0.0/g" ./set_node_attr.txt
