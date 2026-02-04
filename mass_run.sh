#!/bin/bash

#source env for run openroad
#. $HOME/OpenROAD-flow-scripts/env.sh

#choose designs for run
#designs="usb_phy spi_top i2c_master_top ac97_top mc_top"
designs="sasc_top"

#run flow for choosen designs
for design in $designs
do
    echo "Processing: $design"
    export design
    sh ./run_flow.sh
done