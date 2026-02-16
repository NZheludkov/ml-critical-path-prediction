##START TIME
set start_time [exec date +%s]

#stage place
set stage "route_label"
exec mkdir -p $stage

#rm old files if exists
if [file exists ./$stage/paths.txt] {
	exec rm ./$stage/paths.txt
}

if [file exists ./$stage/critical_nets.txt] {
	exec rm ./$stage/critical_nets.txt
}

if [file exists ./$stage/critical_paths_summary.txt] {
	exec rm ./$stage/critical_paths_summary.txt
}

if [file exists ./$stage/net_labels.csv] {
	exec rm ./$stage/net_labels.csv
}

#get unique reg2reg paths
foreach endpoint [sta::endpoints] {
	set endpoint [get_full_name $endpoint]
	set a [find_timing_paths -path_group reg2reg -unique_edges_to_endpoint -unique_paths_to_endpoint -sort_by_slack -to $endpoint]
	if {$a ne ""} {
		report_checks -path_group reg2reg -unique_edges_to_endpoint -unique_paths_to_endpoint -to $endpoint -path_delay max -digits 3 -format summary >> ./$stage/paths.txt
	}
}

#report critical nets
source $flow_dir/flow_scripts/report_critical_path.tcl

#get critical net, labeled
source $flow_dir/flow_scripts/get_critical_net.tcl

##END TIME
set end_time [exec date +%s]
set get_net_labels_route_time [expr $end_time - $start_time]

