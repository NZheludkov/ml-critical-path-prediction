#rm old files if exists
if [file exists ./paths.txt] {
	exec rm ./paths.txt
}

if [file exists ./critical_nets.txt] {
	exec rm ./critical_nets.txt
}

if [file exists ./critical_paths_summary.txt] {
	exec rm ./critical_paths_summary.txt
}

if [file exists ./net_labels.csv] {
	exec rm ./net_labels.csv
}

#get unique reg2reg paths
foreach endpoint [sta::endpoints] {
	set endpoint [get_full_name $endpoint]
	set a [find_timing_paths -path_group reg2reg -unique_edges_to_endpoint -unique_paths_to_endpoint -sort_by_slack -to $endpoint]
	if {$a ne ""} {
		report_checks -path_group reg2reg -unique_edges_to_endpoint -unique_paths_to_endpoint -to $endpoint -path_delay max -digits 3 -format summary >> ./paths.txt
	}
}

#report critical nets
source $flow_dir/flow_scripts/report_critical_path.tcl

#get critical net, labeled
source $flow_dir/flow_scripts/get_critical_net.tcl

