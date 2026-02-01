##db_units_per_micron
set db [::ord::get_db]
set block [[$db getChips] getBlock]
set db_units_per_micron [expr double([$block getDbUnitsPerMicron])]

set block_llx [expr [[$block getBBox] xMin] / $db_units_per_micron]
set block_lly [expr [[$block getBBox] yMin] / $db_units_per_micron]
set block_urx [expr [[$block getBBox] xMax] / $db_units_per_micron]
set block_ury [expr [[$block getBBox] yMax] / $db_units_per_micron]

#get all nets without power ground
set nets [get_full_name_list [get_nets *]]
set idx1 [lsearch $nets "VDD"]
set idx2 [lsearch $nets "VSS"]
set nets [lreplace $nets $idx1 $idx1]

#create dictionary to conserve nets features
set dict_nets {}

#iterate by each net
foreach net $nets {

	#get net db name
	set net_db_name [get_nets $net]
	dict set dict_nets $net "net_db_name" $net_db_name

	#get net odb name
	set net_odb_name [sta::sta_to_db_net [get_nets $net]]
	dict set dict_nets $net "net_odb_name" $net_odb_name

	#get net terms
	dict set dict_nets $net "terms" [$net_odb_name getTermCount]

	#net is port (1 - true; 0 -false)
	if {[get_ports $net] ne ""} {
		dict set dict_nets $net "is_port" "1"
	} else {
		dict set dict_nets $net "is_port" "0"
	}

	#fanin nets (number of nets connected with driver cell)

	#driver area

	#sinks area
	

	#net term bbox xmin
	dict set dict_nets $net "term_bbox_xmin" [expr [[$net_odb_name getTermBBox] xMin] / $db_units_per_micron]

	#net term bbox ymin
	dict set dict_nets $net "term_bbox_ymin" [expr [[$net_odb_name getTermBBox] yMin] / $db_units_per_micron]

	#net term bbox xmax
	dict set dict_nets $net "term_bbox_xmax" [expr [[$net_odb_name getTermBBox] xMax] / $db_units_per_micron]

	#net term bbox ymax
	dict set dict_nets $net "term_bbox_ymax" [expr [[$net_odb_name getTermBBox] yMax] / $db_units_per_micron]

	#net bbox dx
	dict set dict_nets $net "term_bbox_dx" [expr [[$net_odb_name getTermBBox] dx] / $db_units_per_micron]

	#net bbox dy
	dict set dict_nets $net "term_bbox_dy" [expr [[$net_odb_name getTermBBox] dy] / $db_units_per_micron]

	#net bbox area
	dict set dict_nets $net "term_bbox_area" [expr [[$net_odb_name getTermBBox] area] / (($db_units_per_micron)**2)]

	#net bbox hpwl
	dict set dict_nets $net "term_bbox_hpwl" [expr ([[$net_odb_name getTermBBox] dx] + [[$net_odb_name getTermBBox] dy]) / $db_units_per_micron]

	#net bbox aspect ration X/Y
	set dx [expr [[$net_odb_name getTermBBox] dx] / $db_units_per_micron]
	set dy [expr [[$net_odb_name getTermBBox] dy] / $db_units_per_micron]
	dict set dict_nets $net "term_bbox_ar" [expr $dx / $dy]

	#net connect with ff/Q (trigger out)
	set driver_is_ff_q 0

	proc is_ff_master {master_name} {
    	# под sky130_fd_sc_hd__dfxtp_*
    	return [expr {[regexp {__df} $master_name] || [regexp {dff} $master_name]}]
	}

	foreach it [$net_odb_name getITerms] {
    	set io [[$it getMTerm] getIoType]
    	set inst [$it getInst]
    	set master [[$inst getMaster] getName]
    	set pin_name [[$it getMTerm] getName]   ;# e.g. Q, D, CLK

    	if {$io eq "OUTPUT"} {
        	if {[is_ff_master $master] && ($pin_name eq "Q" || [regexp {^Q$} $pin_name])} {
            	set driver_is_ff_q 1
        	}
    	}
    
	}

	dict set dict_nets $net "driver_is_ff_q" $driver_is_ff_q

	#net connected with ff/D (trigger in)
	set sink_is_ff_d 0

	foreach it [$net_odb_name getITerms] {
    	set io [[$it getMTerm] getIoType]
    	set inst [$it getInst]
    	set master [[$inst getMaster] getName]
    	set pin_name [[$it getMTerm] getName]   ;# e.g. Q, D, CLK

    	if {$io eq "INPUT"} {
        	if {[is_ff_master $master] && ($pin_name eq "D" || [regexp {^D$} $pin_name])} {
            	set sink_is_ff_d 1
        	}
    	}
    
	}

	dict set dict_nets $net "sink_is_ff_d" $sink_is_ff_d

}