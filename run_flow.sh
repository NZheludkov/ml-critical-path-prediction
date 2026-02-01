#!/bin/bash

#source env for run openroad
#. $HOME/OpenROAD-flow-scripts/env.sh

#Choose design for flow
design="usb_phy"

#set rtl dataset path
rtl_dataset_path="$HOME/RTL-Dataset"

#set pdk path
pdk_path="$HOME/skywater-pdk"

#set flow repo dir
flow_dir="$HOME/phd/ml-critical-path-prediction"

#createa base dir
mkdir -p designs

#create dir for block
mkdir -p designs/$design

#create yosys and openroad dirs
mkdir -p designs/$design/yosys
mkdir -p designs/$design/openroad

#exports vars
export design
export HOME
export rtl_dataset_path
export pdk_path
export flow_dir

#run synt in yosys
cd $flow_dir/designs/$design/yosys/
yosys $flow_dir/flow_scripts/run_yosys.tcl

#run flow in openroad
cd $flow_dir/designs/$design/openroad/
openroad -threads 4 -gui -log ./log.txt \
-metrics metrics.txt \
$flow_dir/flow_scripts/run_openroad.tcl