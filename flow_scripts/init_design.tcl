##START TIME
set start_time [exec date +%s]

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
read_sdc $rtl_dataset_path/designs/$design/sdc/func.tcl

##CREATE PATH GROUP
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name in2reg -from [all_inputs] -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]
group_path -name in2out -from [all_inputs] -to [all_outputs]

#get netlist size (cells and nets)
set cells_number [llength [get_cells *]]
set nets_number [llength [get_nets *]]

##END TIME
set end_time [exec date +%s]
set init_design_time [expr $end_time - $start_time]