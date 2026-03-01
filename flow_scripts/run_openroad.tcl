#extract vars
set design $env(design)
set HOME $env(HOME)
set rtl_dataset_path $env(rtl_dataset_path)
set pdk_path $env(pdk_path)
set flow_dir $env(flow_dir)

#source design config
source $rtl_dataset_path/designs/$design/config.tcl

#source procs
source $flow_dir/flow_scripts/procs.tcl

#init design
source $flow_dir/flow_scripts/init_design.tcl

#create floorplan
source $flow_dir/flow_scripts/create_floorplan.tcl

#prects 
source $flow_dir/flow_scripts/prects.tcl

#extract net load features
source $flow_dir/flow_scripts/extract_net_load_feats.tcl

#cts 
source $flow_dir/flow_scripts/cts.tcl

#postcts 
source $flow_dir/flow_scripts/postcts.tcl

#route 
source $flow_dir/flow_scripts/route.tcl

#extract net load labels
source $flow_dir/flow_scripts/extract_net_load_labels.tcl

#dataset 
source $flow_dir/flow_scripts/create_dataset.tcl



