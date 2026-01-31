#extract vars
set design $env(design)
set HOME $env(HOME)
set rtl_dataset_path $env(rtl_dataset_path)
set pdk_path $env(pdk_path)

#source design config
source $rtl_dataset_path/designs/$design/config.tcl

#init design
source $HOME/CapPredictionOpenROAD/flow_scripts/init_design.tcl

#create floorplan
source $HOME/CapPredictionOpenROAD/flow_scripts/create_floorplan.tcl

#prects 
source $HOME/CapPredictionOpenROAD/flow_scripts/prects.tcl

#cts 
source $HOME/CapPredictionOpenROAD/flow_scripts/cts.tcl

#postcts 
source $HOME/CapPredictionOpenROAD/flow_scripts/postcts.tcl

#route 
source $HOME/CapPredictionOpenROAD/flow_scripts/route.tcl

