##START TIME
set start_time [exec date +%s]

##ROUTE SETTINGS
set_routing_layers -signal met1-met5 -clock met1-met5
 
#GLOBAL ROUTE
global_route -allow_congestion -verbose -guide_file ./groute.guide

##FIX SLEW,FANOUT,CAP (DRV)
repair_design -verbose

##FIX SETUP 1
repair_timing -setup -verbose -repair_tns 100

##FIX HOLD 1
repair_timing -hold -allow_setup_violations

##FIX SETUP 2
repair_timing -setup -verbose -repair_tns 100

##FIX HOLD 2
repair_timing -hold -allow_setup_violations

##DETAIL PLACEMENT AFTER ADDING CTS BUFS
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

##ADD TIELO TIEHI
insert_tiecells -prefix TIE sky130_fd_sc_hd__conb_1/HI
insert_tiecells -prefix TIE sky130_fd_sc_hd__conb_1/LO

repair_tie_fanout -verbose sky130_fd_sc_hd__conb_1/HI
repair_tie_fanout -verbose sky130_fd_sc_hd__conb_1/LO

##PLACE TIE CELLS
detailed_placement

##OPTIMIZE PLACE BY MIRRORING CELL
optimize_mirroring

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

##DETAIL ROUTE
detailed_route \
-droute_end_iter "5" \
-verbose "10" \
-output_drc ./drc_report.txt \
-db_process_node "130"

##EVAL SPEF
estimate_parasitics -global_routing

##REPORT TIMING AFTER DROUTE
exec mkdir -p ./timing_reports/route/
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/route/in2reg_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/route/reg2reg_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/route/reg2out_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/route/in2out_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/route/in2reg_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/route/reg2reg_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/route/reg2out_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/route/in2out_hold.txt

##RC EXTRACTION
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file "/home/nzheludkov/Downloads/open_pdks-refs_tags_1.0.341-sky130-openlane/rules.openrcx.sky130A.max.spef_extractor" \
-cc_model 12 -max_res 0 -context_depth 10 \
-coupling_threshold 0.1

##WRITE AND READ SPEF
write_spef ./spef.spef
read_spef ./spef.spef -corner ss_1p60v_m40c -max

##REPORT TIMING AFTER DROUTE
exec mkdir -p ./timing_reports/route_spef/
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/route_spef/in2reg_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/route_spef/reg2reg_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/route_spef/reg2out_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/route_spef/in2out_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/route_spef/in2reg_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/route_spef/reg2reg_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/route_spef/reg2out_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/route_spef/in2out_hold.txt

##WRITE WNS
with_output_to_variable a {report_checks -path_group reg2reg -digits 3 -format slack_only -no_line_splits}
set wns [lindex $a 4]

##WRITE ROUTE DATA
exec mkdir -p ./route/def/
exec mkdir -p ./route/netlist/
exec mkdir -p ./route/sdc/
exec mkdir -p ./route/spef/
exec mkdir -p ./route/sdf/

write_def ./route/def/def.def
write_verilog -remove_cells "*fill* *cap*" ./route/netlist/netlist.v
write_sdc ./route/sdc/sdc.sdc
write_spef ./route/spef/spef.spef
write_sdf -digits 3 -corner ss_1p60v_m40c ./route/sdf/sdf.sdf

##END TIME
set end_time [exec date +%s]
set route_time [expr $end_time - $start_time]