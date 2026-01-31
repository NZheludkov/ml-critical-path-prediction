##TCL MODE
yosys -import

#extract vars
set design $env(design)
set HOME $env(HOME)
set rtl_dataset_path $env(rtl_dataset_path)
set pdk_path $env(pdk_path)

#set MAN_MODE $env(MAN_MODE)
#if { ${MAN_MODE} } { source ../config.tcl } else { source config.tcl }

#read rtl
set rtl_list [glob $rtl_dataset_path/designs/$design/rtl/*.v]
foreach rtl $rtl_list {
	read_verilog $rtl
}
	
##READ LIBERTY LATCH
read_liberty -ignore_miss_func -ignore_miss_dir -ignore_miss_data_latch -lib "$pdk_path/libraries/sky130_fd_sc_hd/latest/timing/sky130_fd_sc_hd__ss_n40C_1v44.lib"

##SYNT
hierarchy -check -top $design
proc_clean
proc_rmdead
proc_prune
proc_init
proc_arst
proc_rom
proc_mux
proc_dlatch
proc_dff
proc_memwr
proc_clean
opt_expr

#flatten or no
flatten


opt_expr
opt_clean
opt -nodffe -nosdff
fsm
opt
wreduce
peepopt
opt_clean
alumacc
share
opt
memory -nomap
opt_clean
opt -fast -full
memory_map
opt -full
techmap
techmap -map $rtl_dataset_path/designs/$design/rtl/latch_map.v
opt -fast
abc -fast
opt -fast
hierarchy -check -top $design
stat
check

opt
opt_clean -purge

##ABC

dfflibmap -liberty "$pdk_path/libraries/sky130_fd_sc_hd/latest/timing/sky130_fd_sc_hd__ss_n40C_1v44.lib"

#set D [expr 10 * 1000]

abc -liberty "$pdk_path/libraries/sky130_fd_sc_hd/latest/timing/sky130_fd_sc_hd__ss_n40C_1v44.lib" \
-dont_use *clk* -dont_use *edfxtp* -dont_use *decap* -dont_use *dly*  -dont_use *diode*  -dont_use *ebuf*  -dont_use *ebuf*  -dont_use *ed*  -dont_use *ei*  -dont_use *lpflow*  -dont_use *probe*  -dont_use *sd*  -dont_use *tap*  -dont_use *bufbuf*  -dont_use *bufinv*  -dont_use *conb*  -dont_use *metal*   -dont_use *diode*  -dont_use *tap*


tee -o ./stat.txt stat -top $design -liberty "$pdk_path/libraries/sky130_fd_sc_hd/latest/timing/sky130_fd_sc_hd__ss_n40C_1v44.lib"

##Clean up the design (just the last step of opt)
#clean
splitnets
clean -purge

##autoname

# write synthesized design
write_verilog -noattr -noexpr -nohex -nodec ./${design}.v