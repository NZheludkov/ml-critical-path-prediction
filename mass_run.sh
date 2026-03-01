#!/bin/bash

#source env for run openroad
#. $HOME/OpenROAD-flow-scripts/env.sh

#choose designs for run
#usb_phy +
#pcm_slv_top + 
#FIR_filter + 
#simple_spi_top +
#sasc_top +
#i2c_master_top +
#ac97_top +
#mc_top +
#sha256 +
#trigonometric +
#des3 +
#aes128_core -
#aes_cipher_top -
#aes_core +
#dynamic_node_top_wrap +
#eth_top -
#spi_top +
#Md5Core +

#WORK
designs_work="\
ac97_top \
aes_core \
des3 \
dynamic_node_top_wrap \
FIR_filter \
i2c_master_top \
mc_top \
Md5Core \
pcm_slv_top \
picosoc \
sasc_top \
sha256 \
simple_spi_top \
spi_top \
trigonometric \
tv80s \
usb_phy
wb_dma_top \
IIR_filter \
jpeg_encoder \
idft_top \
gng \
fht \
wbqspiflash \
point_scalar_mult \
keccak \
xge_mac \
RS_dec \
spiMaster \
uart_top \
dmx_tx \
pci_bridge32 \
xtea \
USFFT64_2B \
MC6803_gen2 \
MIPS32_Processor \
aes128_core \
aes_cipher_top \
sdrc_top \
ima_adpcm_dec \
ima_adpcm_enc \
BRSFmnCE \
vga_enh_top \
"
#WORK BUT LONG
designs_work="\
streamScaler \
gfx_top \
or1200_top_cm4_top \
rvx \
z80_core_top \
"

#NOT WORK
designs_no_work="\
wb_conmax_top \
gfx_top \
fftmain \
ifftmain \
openMSP430 \
hpdmc \
ddr3_top \
mpeg2video \
nova \
gost_28147_89 \
sdram \
AltOR32 \
"

designs="\
AltOR32 \
"

#run flow for choosen designs
for design in $designs
do
    echo "Processing: $design"
    export design
    sh ./run_flow.sh
done