#!/bin/bash

#source env for run openroad
#. $HOME/OpenROAD-flow-scripts/env.sh

#Choose design for flow
design="ac97_top"

#set rtl dataset path
rtl_dataset_path="$HOME/RTL-Dataset"

#set pdk path
pdk_path="$HOME/skywater-pdk"

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

#run synt in yosys
cd $HOME/CapPredictionOpenROAD/designs/$design/yosys/
yosys ../../../flow_scripts/run_yosys.tcl

#run flow in openroad
cd $HOME/CapPredictionOpenROAD/designs/$design/openroad/
openroad -threads 4 -gui -log ./log.txt \
-metrics metrics.txt \
../../../flow_scripts/run_openroad.tcl