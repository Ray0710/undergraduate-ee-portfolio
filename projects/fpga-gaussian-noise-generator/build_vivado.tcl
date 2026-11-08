# Run from the staged build directory; project uses only S7-25 source files.
set part xc7s25csga324-1
create_project awgn_s7_25 ./project -part $part -force
set_property target_language Verilog [current_project]
add_files [glob ./rtl/*.v]
add_files [glob ./*.mem]
add_files -fileset constrs_1 ./constraints/arty_s7_25_awgn.xdc
add_files -fileset sim_1 [glob ./sim/*.sv]
set_property top tb_validation [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property top awgn_s7_25_top [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
open_run synth_1
report_utilization -file synthesis_utilization.rpt
report_io -file synthesis_io.rpt
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_utilization -file implementation_utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing_summary.rpt
report_drc -file drc.rpt
report_io -file io.rpt
check_timing -verbose -file check_timing.rpt
write_checkpoint -force awgn_s7_25_routed.dcp
set n [llength [get_ports]]
if {$n != 7} {error "Expected 7 ports, found $n"}
if {[llength [get_timing_paths -quiet -slack_lesser_than 0]] > 0} {error "Timing failed"}
if {[llength [get_timing_paths -quiet -delay_type min -slack_lesser_than 0]] > 0} {error "Hold timing failed"}
puts "PASS S7-25: routed, bitstream generated, 7 ports, timing met"
close_project
