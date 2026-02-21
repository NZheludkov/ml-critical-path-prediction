#!/bin/bash

#source env for run openroad
#. $HOME/OpenROAD-flow-scripts/env.sh

#choose designs for run
#designs="usb_phy spi_top i2c_master_top ac97_top mc_top"
#designs="aes_cipher_top pci_bridge32 pcm_slv_top aes128_core"
#designs="usb_phy"

#AVAILABLE DESIGNS
#ac97_top  aes_cipher_top  dynamic_node_top_wrap  i2c_master_top  mc_top  pcm_slv_top  sasc_top  sha256  simple_spi_top  spi_top  usb_phy

#designs="ac97_top aes_cipher_top dynamic_node_top_wrap i2c_master_top mc_top sasc_top  sha256 simple_spi_top spi_top pcm_slv_top usb_phy FIR_filter"
designs="\
usb_phy \
pcm_slv_top \
FIR_filter \
spi_top \
simple_spi_top \
sasc_top \
i2c_master_top \
ac97_top \
mc_top \
sha256 \
"

designs="\
usb_phy
"

#run flow for choosen designs
for design in $designs
do
    echo "Processing: $design"
    export design
    sh ./run_flow.sh
done