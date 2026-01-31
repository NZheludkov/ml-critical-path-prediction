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

repair_design -verbose

repair_timing -setup -verbose

detailed_placement

optimize_mirroring

#check_placement

##EVAL SPEF
estimate_parasitics -placement

##REPORT TIMING AFTER PRECTS
exec mkdir -p ./timing_reports/prects/
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap fanout} -path_group in2reg  > ./timing_reports/prects/in2reg.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap fanout} -path_group reg2reg > ./timing_reports/prects/reg2reg.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap fanout} -path_group reg2out > ./timing_reports/prects/reg2out.txt
report_checks -corner ss_1p60v_m40c -digits 3 -path_delay max -no_line_splits -fields {slew net cap fanout} -path_group in2out  > ./timing_reports/prects/in2out.txt

##WRITE ROUTE DATA
exec mkdir -p ./prects/def/
exec mkdir -p ./prects/netlist/
exec mkdir -p ./prects/sdc/
exec mkdir -p ./prects/sdf/

write_def ./prects/def/def.def
write_verilog -remove_cells "*fill* *cap*" ./prects/netlist/netlist.v
write_sdc ./prects/sdc/sdc.sdc
write_sdf -digits 3 -corner ss_1p60v_m40c ./prects/sdf/sdf.sdf