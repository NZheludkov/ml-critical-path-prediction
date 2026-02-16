##START TIME
set start_time [exec date +%s]

##POSTCTS (FIX DRV, SETUP, HOLD)
##FIX SLEW,FANOUT,CAP (DRV)
repair_design -verbose

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

##EVAL SPEF
estimate_parasitics -placement

##REPORT TIMING AFTER POSTCTS
exec mkdir -p ./timing_reports/postcts/
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/postcts/in2reg_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/postcts/reg2reg_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/postcts/reg2out_setup.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/postcts/in2out_setup.txt

report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/postcts/in2reg_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/postcts/reg2reg_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/postcts/reg2out_hold.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay min -format full_clock_expanded -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/postcts/in2out_hold.txt

##WRITE ROUTE DATA
exec mkdir -p ./postcts/def/
exec mkdir -p ./postcts/netlist/
exec mkdir -p ./postcts/sdc/
exec mkdir -p ./postcts/sdf/

write_def ./postcts/def/def.def
write_verilog -remove_cells "*fill* *cap*" ./postcts/netlist/netlist.v
write_sdc ./postcts/sdc/sdc.sdc
write_sdf -digits 3 -corner ss_1p60v_m40c ./postcts/sdf/sdf.sdf

##END TIME
set end_time [exec date +%s]
set postcts_time [expr $end_time - $start_time]