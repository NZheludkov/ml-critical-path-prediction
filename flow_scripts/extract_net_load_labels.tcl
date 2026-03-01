##START TIME
set start_time [exec date +%s]

#PROCS
proc write_dict_nets_label_csv {dict_nets filename} {

    # открыть файл
    set fp [open $filename "w"]

    # ---- сформировать заголовок (по первому элементу словаря) ----
    set first_net [lindex [dict keys $dict_nets] 0]
    set feature_keys [dict keys [dict get $dict_nets $first_net]]
	set idx1 [lsearch -exact $feature_keys "wire_capacitance_spef"]
    set idx2 [lsearch -exact $feature_keys "routed_length"]
	set f1 [lindex $feature_keys $idx1]
    set f2 [lindex $feature_keys $idx2]
    set feature_keys [concat $f1 $f2]
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

proc add_routed_lengths_from_file {dict_nets filename} {

    # список net, для которых длина найдена
    set nets_with_length {}

    set fp [open $filename r]

    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line eq ""} { continue }

        set tokens [split $line]
        if {[llength $tokens] < 4} { continue }

        set net_raw [lindex $tokens 1]
        set length  [lindex $tokens 2]

        # пробуем как есть
        if {[dict exists $dict_nets $net_raw]} {
            dict set dict_nets $net_raw routed_length $length
            lappend nets_with_length $net_raw
            continue
        }

        # пробуем экранированный вариант
        set net_esc [string map {"[" "\\[" "]" "\\]"} $net_raw]
        if {[dict exists $dict_nets $net_esc]} {
            dict set dict_nets $net_esc routed_length $length
            lappend nets_with_length $net_esc
            continue
        }
    }

    close $fp

    # --- добавляем заглушку для отсутствующих ---
    foreach net [dict keys $dict_nets] {
        if {![dict exists $dict_nets $net routed_length]} {
            dict set dict_nets $net routed_length "0.0"
        }
    }

    return $dict_nets
}

#WRITE WIRE LENGTHS
report_wire_length -detailed_route -net [get_nets *] -file ./wirelength.txt
set dict_nets [add_routed_lengths_from_file $dict_nets "./wirelength.txt"]

#LOAD SPEF
read_spef ./route/spef/spef.spef -corner ss_1p60v_m40c -max

#report_parasitic_annotation
report_parasitic_annotation -report_unannotated > ./report_parasitics_annotation.txt

foreach net [dict keys $dict_nets] {
	set wire_capacitance_spef [expr roundto([[dict get $dict_nets $net net_db_name] wire_capacitance $corner max],4)]
	dict set dict_nets $net "wire_capacitance_spef" $wire_capacitance_spef
}

exec mkdir -p ./labels/
write_dict_nets_label_csv $dict_nets "./labels/nets_load_labels.csv"

##END TIME
set end_time [exec date +%s]
set extract_net_load_labels [expr $end_time - $start_time]