##START TIME
set start_time [exec date +%s]

##CREATE FP
initialize_floorplan -utilization $CU -core_space 3 -aspect_ratio $AR -site unithd

##INIT ROWS (ADD ENDCAP and TRACKS)  
tapcell -endcap_master sky130_fd_sc_hd__fill_1

##CREATE LAYER TRACKS
make_tracks

##CREATE POWER GROUND GRID
pdngen -reset

add_global_connection -net VDD -pin_pattern "VPWR" -power
add_global_connection -net VSS -pin_pattern "VGND" -ground

global_connect

set_voltage_domain -name Core -power VDD -ground VSS
define_pdn_grid -name Core -voltage_domain Core 

add_pdn_stripe -layer met5 -width $PDN_HWIDTH -offset 1  -pitch $PDN_HPITCH -spacing $PDN_HSPACING  -grid Core
add_pdn_stripe -layer met4 -width $PDN_VWIDTH -offset 1  -pitch $PDN_VPITCH -spacing $PDN_VSPACING  -grid Core
add_pdn_stripe -layer met1 -width 0.49 -grid Core -followpins

add_pdn_connect -layers {met1 met4} -grid Core
add_pdn_connect -layers {met4 met5} -grid Core

pdngen

##ADD PINS
place_pins -hor_layers {met3 met5} -ver_layers {met2 met4} -min_distance_in_tracks -min_distance 4

##END TIME
set end_time [exec date +%s]
set create_floorplan_time [expr $end_time - $start_time]