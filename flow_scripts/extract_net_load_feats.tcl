##START TIME
set start_time [exec date +%s]

#PROCS
proc write_dict_nets_csv {dict_nets filename} {

    # открыть файл
    set fp [open $filename "w"]

    # ---- сформировать заголовок (по первому элементу словаря) ----
    set first_net [lindex [dict keys $dict_nets] 0]
    set feature_keys [dict keys [dict get $dict_nets $first_net]]
    set idx [lsearch -exact $feature_keys "net_db_name"]
    set feature_keys [lreplace $feature_keys $idx $idx]
    set idx [lsearch -exact $feature_keys "net_odb_name"]
    set feature_keys [lreplace $feature_keys $idx $idx]

    puts $fp "net,[join $feature_keys ,]"

    # ---- запись строк ----
    dict for {net feats} $dict_nets {
        set row [list $net]
        foreach key $feature_keys {
            lappend row [dict get $feats $key]
        }
        puts $fp [join $row ,]
    }

    close $fp
}

proc get_net_driver {net_name} {
  set db    [ord::get_db]
  set chip  [$db getChip]
  set block [$chip getBlock]

  # 0) escape [ ] so OpenDB can find the net
  set esc_name [string map {"[" "\\[" "]" "\\]"} $net_name]

  set net [$block findNet $esc_name]
  if {$net eq "" || $net eq "NULL"} {
    return ""
  }

  # 1) CELL driver: OUTPUT iterm
  foreach it [$net getITerms] {
    if {[catch { set t [$it getIoType] }]} { continue }
    if {$t eq "OUTPUT"} {
      set inst [$it getInst]
      if {$inst ne ""} { return [$inst getName] }
    }
  }

  # 2) PORT driver: INPUT bterm (net of input port)
  foreach bt [$net getBTerms] {
    set t "UNKNOWN"
    catch { set t [$bt getIoType] }
    if {$t eq "INPUT"} { return [$bt getName] }
  }

  # 3) fallback: any port on this net (если надо)
  set bterms [$net getBTerms]
  if {[llength $bterms] > 0} {
    return [[lindex $bterms 0] getName]
  }

  return ""
}


proc tcl::mathfunc::roundto {value sigfigs} {

    # Обработка нуля
    if {$value == 0.0} {
        return 0.0
    }

    # Работаем с модулем (для отрицательных)
    set sign 1
    if {$value < 0} {
        set sign -1
        set value [expr {abs($value)}]
    }

    set pow [expr {($sigfigs - 1) - floor(log10($value))}]
    set result [expr {round(10.0**$pow * $value) / 10.0**$pow}]

    return [expr {$sign * $result}]
}

##db_units_per_micron
set db [::ord::get_db]
set block [[$db getChips] getBlock]
set db_units_per_micron [expr double([$block getDbUnitsPerMicron])]
set corner [lindex [sta::corners] 0]

set block_llx [expr [[$block getBBox] xMin] / $db_units_per_micron]
set block_lly [expr [[$block getBBox] yMin] / $db_units_per_micron]
set block_urx [expr [[$block getBBox] xMax] / $db_units_per_micron]
set block_ury [expr [[$block getBBox] yMax] / $db_units_per_micron]

#get all nets without power ground
set nets [get_full_name_list [get_nets *]]

set nets_filtered $nets

# удалить все VSS
set idx [lsearch -exact $nets_filtered "VSS"]
while {$idx != -1} {
    set nets_filtered [lreplace $nets_filtered $idx $idx]
    set idx [lsearch -exact $nets_filtered "VSS"]
}

# удалить все VDD
set idx [lsearch -exact $nets_filtered "VDD"]
while {$idx != -1} {
    set nets_filtered [lreplace $nets_filtered $idx $idx]
    set idx [lsearch -exact $nets_filtered "VDD"]
}

#remove clk nets
set idx [lsearch -exact $nets_filtered $clock]
while {$idx != -1} {
    set nets_filtered [lreplace $nets_filtered $idx $idx]
    set idx [lsearch -exact $nets_filtered $clock]
}

# результат
set nets $nets_filtered

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

  #net is port (1 - true; 0 - false)
  if {[get_ports $net] ne ""} {
    set is_port 1
    dict set dict_nets $net is_port $is_port
    set port_direction [get_property -object_type port $net direction]
  } else {
    set is_port 0
    dict set dict_nets $net is_port $is_port
  }

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
	dict set dict_nets $net "term_bbox_area" [expr roundto([[$net_odb_name getTermBBox] area] / (($db_units_per_micron)**2),4)]

	#net bbox hpwl
	dict set dict_nets $net "term_bbox_hpwl" [expr roundto(([[$net_odb_name getTermBBox] dx] + [[$net_odb_name getTermBBox] dy]) / $db_units_per_micron,3)]

	#net bbox aspect ration X/Y
	set dx [expr [[$net_odb_name getTermBBox] dx] / $db_units_per_micron + 1e-8]
	set dy [expr [[$net_odb_name getTermBBox] dy] / $db_units_per_micron + 1e-8]
	dict set dict_nets $net "term_bbox_ar" [expr roundto([expr $dx / $dy],3)]
	
  #wire capacitance estimated by openroad (estimate_parasitics -placement)
  set wire_capacitance_placement [expr roundto([$net_db_name wire_capacitance $corner max],3)]
  dict set dict_nets $net "wire_capacitance_placement" $wire_capacitance_placement

  #pins capacitance
  if {$is_port && $port_direction eq "output"} {
    set pin_capacitance 0.0
  } else {
    set pin_capacitance [expr {roundto([$net_db_name pin_capacitance $corner max], 3)}]
  }
  dict set dict_nets $net pin_capacitance $pin_capacitance

  #driving inst
  if {$is_port eq "0"} {
    #set driving_inst [get_full_name [get_fanin -to $net -levels 1 -only_cells]]
    set driving_inst [get_net_driver $net]
    set driving_inst_db [get_cells [get_net_driver $net]]
    dict set dict_nets $net "driving_inst" $driving_inst

    #driving cell
    set driving_cell [[$driving_inst_db liberty_cell] name]
    dict set dict_nets $net "driving_cell" $driving_cell

    #driver cell is inverter
    set is_inverter [[$driving_inst_db liberty_cell] is_inverter]
    dict set dict_nets $net "is_inverter" $is_inverter

    #driving cell drive strength
    if {[regexp {_(\d+)$} $driving_cell -> strength]} {
      set driving_cell_strength $strength
    }
    dict set dict_nets $net "driving_cell_strength" $driving_cell_strength

    #driver cell is buffer
    set is_buffer [[$driving_inst_db liberty_cell] is_buffer]
    dict set dict_nets $net "is_buffer" $is_buffer
    
    #fanin (number of driving cell pins)
    set fanin [llength [get_pins -of [get_cells $driving_inst] -filter "direction == input"]]
    dict set dict_nets $net "fanin" $fanin

    #driving_cell_area
    set driving_cell_area [expr roundto([get_property -object_type liberty_cell $driving_cell area],3)]
    dict set dict_nets $net "driving_cell_area" $driving_cell_area

    #fanout area
    set fanout_area 0
    foreach term [$net_odb_name getITerms] {
      if {[[$term getInst] getName] ne $driving_inst} {
        set inst_area [get_property -object_type liberty_cell [get_lib_cells -of [[$term getInst] getName]] area]
        set fanout_area [expr roundto($fanout_area + $inst_area,4)]
      }
    }
    dict set dict_nets $net "fanout_area" $fanout_area

  } else {
    dict set dict_nets $net "driving_inst" "port"
    dict set dict_nets $net "driving_cell" "port"
    dict set dict_nets $net "driving_cell_strength" "port"
    dict set dict_nets $net "is_inverter" "0"
    dict set dict_nets $net "is_buffer" "0"
    dict set dict_nets $net "fanin" "0"
    dict set dict_nets $net "driving_cell_area" "0"
    dict set dict_nets $net "fanout_area" "0"
  }

}

exec mkdir -p ./features/
write_dict_nets_csv $dict_nets "./features/nets_load_features.csv"

##END TIME
set end_time [exec date +%s]
set extract_net_load_feats [expr $end_time - $start_time]






