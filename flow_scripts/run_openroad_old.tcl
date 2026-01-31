#extract vars
set design $env(design)
set HOME $env(HOME)
set rtl_dataset_path $env(rtl_dataset_path)
set pdk_path $env(pdk_path)

##CREATE LEF LIST
set tech_lef "${pdk_path}/libraries/sky130_fd_sc_hd/latest/tech/sky130_fd_sc_hd.tlef"
set cells_lef [exec find ${pdk_path}/libraries/sky130_fd_sc_hd/latest/cells/ -name "*lef*" ! -name "*magic*" ! -name "*tap*"]
set lef_list [concat $tech_lef $cells_lef]

##LIBERTY LIST
set liberty_list "${pdk_path}/libraries/sky130_fd_sc_hd/latest/timing/sky130_fd_sc_hd__ss_n40C_1v60.lib"

##UNITS
set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um
 
##CREATE TIMING CORNER
define_corners ss_1p60v_m40c

##READ LEF LIST
foreach lef $lef_list {
	read_lef $lef
}

##READ LIBERTY FILES
foreach lib $liberty_list {
	read_liberty -corner ss_1p60v_m40c $lib
}

##READ NETLIST
read_verilog ../yosys/${design}.v
link_design $design

##READ SDC
read_sdc ../data_in/sdc/func.tcl

##CREATE PATH GROUP
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name in2reg -from [all_inputs] -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]
group_path -name in2out -from [all_inputs] -to [all_outputs]

##CREATE FP
initialize_floorplan -utilization 30 -core_space 5 -aspect_ratio 1 -site unithd

##INIT ROWS (ADD ENDCAP and TRACKS)  
place_endcaps -endcap "sky130_fd_sc_hd__fill_1"

##CREATE LAYER TRACKS
make_tracks

##CREATE POWER GROUND GRID
set db [::ord::get_db]
set block [[$db getChips] getBlock]
set db_units_per_micron [$block getDbUnitsPerMicron]

pdngen -reset

add_global_connection -net VDD -pin_pattern "VPWR" -power
add_global_connection -net VSS -pin_pattern "VGND" -ground

global_connect

set_voltage_domain -name Core -power VDD -ground VSS
define_pdn_grid -name Core -voltage_domain Core 

add_pdn_stripe -layer met5 -width 6 -offset 1  -pitch 18 -spacing 2  -grid Core
add_pdn_stripe -layer met4 -width 3 -offset 1  -pitch 12 -spacing 0.6  -grid Core
add_pdn_stripe -layer met1 -width 0.49 -grid Core -followpins

add_pdn_connect -layers {met1 met4} -grid Core
add_pdn_connect -layers {met4 met5} -grid Core

pdngen

##ADD PINS
set_pin_length -hor_length 3.2 -ver_length 3.2
place_pins -hor_layers {met3 met5} -ver_layers {met2 met4} -min_distance_in_tracks \
-min_distance 4

##DONT USE LIST
set_dont_use *clk*
set_dont_use *decap*
set_dont_use *dly*
set_dont_use *diode*
set_dont_use *ebuf*
set_dont_use *ebuf*
set_dont_use *ed*
set_dont_use *ei*
set_dont_use *lpflow*
set_dont_use *probe*
set_dont_use *sd*
set_dont_use *tap*
set_dont_use *bufbuf*
set_dont_use *bufinv*
set_dont_use *conb*
set_dont_use *metal*
set_dont_use *diode*
set_dont_use *tap*

##ROUTING LAYERS
set_routing_layers -signal met1-met5 -clock met1-met5

##LAYER FOR RC ESTIMATION
set_wire_rc -clock -layer met3
set_wire_rc -signal -layer met3

##SET ALL CLOCKS TO IDEL (NOT PROPAGATED)
unset_propagated_clock [all_clocks]

remove_buffers 

global_placement \
-routability_driven \
-overflow "0.05" \
-density "0.7" \
-init_density_penalty "1e-2" \
-pad_left "2"

detailed_placement

estimate_parasitics -placement

#repair_design

repair_timing -setup -verbose

detailed_placement

optimize_mirroring

#check_placement

##EVAL SPEF
estimate_parasitics -placement

##REPORT TIMING AFTER PRECTS
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -path_group in2reg  >> ./reports/prects_in2reg.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -path_group reg2reg >> ./reports/prects_reg2reg.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -path_group reg2out >> ./reports/prects_reg2out.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -path_group in2out  >> ./reports/prects_in2out.txt

##PROPAGATE ALL CLOCKS
set_propagated_clock [all_clocks]

##MAX SLEW AND MAX CAP FOR CTS
set max_slew [expr 0.5 * 1e-9]; # must convert to seconds
set max_cap  [expr 0.3 * 1e-12]; # must convert to farad

##EVAL SPEF
estimate_parasitics -placement

#Clone clock tree inverters next to register loads
#so cts does not try to buffer the inverted clocks.
repair_clock_inverters

##CTS CONFIG
configure_cts_characterization\
    -max_slew $max_slew\
    -max_cap $max_cap

##CTS
clock_tree_synthesis \
    -buf_list "sky130_fd_sc_hd__clkinv_2 sky130_fd_sc_hd__clkinv_4 sky130_fd_sc_hd__clkinv_8" \
    -root_buf "sky130_fd_sc_hd__clkbuf_2"

##CTS REPORT
report_cts -out_file ./cts_report.txt
report_clock_skew -digits 3 > ./report_skew.txt

##DETAIL PLACEMENT AFTER ADDING CTS BUFS
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

##WRITE_DEF NETLIST CTS
#write_def ./defs/${design}_cts.def
#write_verilog  -remove_cells "*fill**"  ./netlists/${design}_cts.v
#write_sdc ./sdc/${design}_cts.sdc

##EVAL SPEF
estimate_parasitics -placement

##REPORT TIMING AFTER CTS (SETUP + HOLD)
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group in2reg \
>> ./reports/cts_in2reg_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2reg \
>> ./reports/cts_reg2reg_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2out \
>> ./reports/cts_reg2out_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group in2out \
>> ./reports/cts_in2out_setup.txt
 
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group in2reg \
>> ./reports/cts_in2reg_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2reg \
>> ./reports/cts_reg2reg_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2out \
>> ./reports/cts_reg2out_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group in2out \
>> ./reports/cts_in2out_hold.txt

##POSTCTS (FIX DRV, SETUP, HOLD)
##FIX SLEW,FANOUT,CAP (DRV)
repair_design

##DETAIL PLACEMENT AFTER ADDING CTS BUFS
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

##EVAL SPEF
estimate_parasitics -placement

##FIX SETUP 1
repair_timing -setup -verbose -repair_tns 100

##FIX HOLD 1
repair_timing -hold -allow_setup_violations

##FIX SETUP 2
repair_timing -setup

##FIX HOLD 2
repair_timing -hold -allow_setup_violations

##DETAIL PLACEMENT AFTER ADDING CTS BUFS
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

##WRITE_DEF NETLIST POSTCTS
#write_def ./defs/${design}_postcts.def
#write_verilog  -remove_cells "*fill*"  ./netlists/${design}_postcts.v
#write_sdc ./sdc/${design}_postcts.sdc

##EVAL SPEF
estimate_parasitics -placement

##REPORT TIMING AFTER POSTCTS (SETUP + HOLD)
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group in2reg \
>> ./reports/post_cts_in2reg_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2reg \
>> ./reports/post_cts_reg2reg_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2out \
>> ./reports/post_cts_reg2out_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock -path_group in2out \
>> ./reports/post_cts_in2out_setup.txt
 
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group in2reg \
>> ./reports/post_cts_in2reg_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2reg \
>> ./reports/post_cts_reg2reg_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group reg2out \
>> ./reports/post_cts_reg2out_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock -path_group in2out \
>> ./reports/post_cts_in2out_hold.txt

##START TIMER
set timer_route [clock seconds]

##ADD TIELO TIEHI
insert_tiecells -prefix TIE sky130_fd_sc_hd__conb_1/HI
insert_tiecells -prefix TIE sky130_fd_sc_hd__conb_1/LO

repair_tie_fanout -verbose sky130_fd_sc_hd__conb_1/HI
repair_tie_fanout -verbose sky130_fd_sc_hd__conb_1/LO

##PLACE TIE CELLS
detailed_placement

##ROUTE SETTINGS
set_routing_layers -signal met1-met5 -clock met1-met5

global_route -allow_congestion -verbose -guide_file ./groute.guide

##EVAL SPEF
estimate_parasitics -global_routing

##ROUTE (FIX DRV, SETUP, HOLD)
##FIX SLEW,FANOUT,CAP (DRV)
#repair_design

#DETAIL PLACEMENT
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

##EVAL SPEF
estimate_parasitics -global_routing

##FIX SETUP 1
repair_timing -setup -verbose -repair_tns 100

##FIX HOLD 1
repair_timing -hold -allow_setup_violations

##FIX SETUP 2
repair_timing -setup

##FIX HOLD 2
repair_timing -hold -allow_setup_violations

##DETAIL PLACEMENT AFTER ADDING CTS BUFS
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

##REPORT TIMING AFTER GLOBAL ROUTE (SETUP + HOLD)
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2reg \
>> ./reports/groute_in2reg_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2reg \
>> ./reports/groute_reg2reg_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2out \
>> ./reports/groute_reg2out_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2out \
>> ./reports/groute_in2out_setup.txt
 
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2reg \
>> ./reports/groute_in2reg_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2reg \
>> ./reports/groute_reg2reg_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2out \
>> ./reports/groute_reg2out_hold.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2out \
>> ./reports/groute_in2out_hold.txt

##ADD FILLER
filler_placement -prefix DCAP "\
sky130_fd_sc_hd__decap_4 
sky130_fd_sc_hd__decap_8 
sky130_fd_sc_hd__fill_1 
sky130_fd_sc_hd__fill_2 
sky130_fd_sc_hd__fill_4 
sky130_fd_sc_hd__fill_8"
 
#GLOBAL ROUTE
global_route -allow_congestion -verbose -guide_file ./groute.guide

#SET BOTTOM-TOP ROUTING LAYERS
set_routing_layers -signal met1-met5 -clock met1-met5

##DETAIL ROUTE
detailed_route \
-droute_end_iter "5" \
-verbose "10" \
-output_drc ./drc_report.txt \
-db_process_node "130"

##WRITE_DEF NETLIST ROUTE
#write_def ./defs/${design}_route.def
#write_verilog -remove_cells "*fill* *cap*" ./netlists/${design}_route.v
#write_sdc ./sdc/${design}_route.sdc

##EVAL SPEF
#estimate_parasitics -global_routing

##RC EXTRACTION
#define_process_corner -ext_model_index 0 X
#extract_parasitics -ext_model_file "../../../flow_scripts/RC_tech_file" \
#-cc_model 12 -max_res 0 -context_depth 10 \
#-coupling_threshold 0.1

##WRITE AND READ SPEF
#write_spef ./spef.spef
#read_spef ./spef.spef -corner ss_1p60v_m40c -max

##REPORT TIMING AFTER ROUTE (SETUP + HOLD)

with_output_to_variable postroute_in2reg_setup "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2reg"
exec echo ${postroute_in2reg_setup} >> ./reports/postroute_in2reg_setup.txt

with_output_to_variable postroute_reg2reg_setup "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2reg"
exec echo ${postroute_reg2reg_setup} >> ./reports/postroute_reg2reg_setup.txt

with_output_to_variable postroute_reg2out_setup "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2out"
exec echo ${postroute_reg2out_setup} >> ./reports/postroute_reg2out_setup.txt

with_output_to_variable postroute_in2out_setup "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2out"
exec echo ${postroute_in2out_setup} >> ./reports/postroute_in2out_setup.txt
 
with_output_to_variable postroute_in2out_setup "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2reg"
exec echo ${postroute_in2out_setup} >> ./reports/postroute_in2reg_hold.txt

with_output_to_variable postroute_reg2reg_hold "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2reg"
exec echo ${postroute_reg2reg_hold} >> ./reports/postroute_reg2reg_hold.txt

with_output_to_variable postroute_reg2out_hold "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group reg2out"
exec echo ${postroute_reg2out_hold} >> ./reports/postroute_reg2out_hold.txt

with_output_to_variable postroute_in2out_hold "report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -no_line_splits -fields {slew net cap} -format full_clock_expanded -path_group in2out"
exec echo ${postroute_in2out_hold} >> ./reports/postroute_in2out_hold.txt


##WRITE METRICS POSTROUTE NO SPEF
#source ../../../flow_scripts/write_metrics_postroute.tcl

##WRITE WORST ACTUAL DELAY FOR 3 BASIC GROUP
#set new_file [open ./actual_delay_postroute.csv w+]
#source ../../../flow_scripts/report_delay.tcl
#close $new_file

##WRITE CONGESTION MAP
gui::dump_heatmap Routing ./congestion_map.txt
gui::dump_heatmap Power ./power_density_map.txt
gui::dump_heatmap Placement ./placement_density_map.txt

##WRITE SDF FILE
#write_sdf -digits 3 ./${design}.sdf

##END TIMER
set timer_route_end [clock seconds]
mem_used
