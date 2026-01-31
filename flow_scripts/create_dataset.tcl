#rm path.txt
if [file exists ./paths.txt] {
	exec rm ./paths.txt
}

#write all paths unique endpoints to paths.txt
foreach sta_path [sta::endpoints] {
	set path [get_full_name $sta_path]
	report_checks -to $path -path_delay max -digits 3 -format summary >> ./paths.txt
}

#report critical nets
source $flow_dir/flow_scripts/report_critical_path.tcl

#get critical net, labeled
source $flow_dir/flow_scripts/get_critical_net.tcl