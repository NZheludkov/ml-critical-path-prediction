#create dataset dir
set dataset_dir "../../../dataset/load_prediction/${design}"
exec mkdir -p $dataset_dir

#cp data
exec cp -r features $dataset_dir
exec cp -r labels $dataset_dir

#write out metrics
set metrics_file "metrics.csv"
set file [open $metrics_file w]

puts $file "design;clock_sdc;wns;cells_number;nets_number;CLK_PERIOD;IO_DELAY;CU;AR;PDN_HWIDTH;PDN_HSPACING;PDN_HPITCH;PDN_VWIDTH;PDN_VSPACING;PDN_VPITCH;init_design;create_floorplan;prects;extract_net_load_feats;cts;postcts;route;extract_net_load_labels"
puts $file "$design;$clock;$wns;$cells_number;$nets_number;$CLK_PERIOD;$IO_DELAY;$CU;$AR;$PDN_HWIDTH;$PDN_HSPACING;$PDN_HPITCH;$PDN_VWIDTH;$PDN_VSPACING;$PDN_VPITCH;$init_design_time;$create_floorplan_time;$prects_time;$extract_net_load_feats;$cts_time;$postcts_time;$route_time;$extract_net_load_labels"
close $file

exec cp -r $metrics_file $dataset_dir
