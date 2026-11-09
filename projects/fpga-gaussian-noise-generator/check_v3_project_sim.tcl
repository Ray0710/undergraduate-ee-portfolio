# Run from the FPGA project directory after building v3.
open_project ./project_v3/awgn_s7_25.xpr
if {[get_property PART [current_project]] ne "xc7s25csga324-1"} {error "Wrong FPGA part"}
if {[get_property TOP [get_filesets sources_1]] ne "awgn_s7_25_pipeline_top"} {error "Wrong RTL top"}
if {[get_property TOP [get_filesets sim_1]] ne "tb_pipeline"} {error "Wrong behavioral top"}
launch_simulation -simset sim_1 -mode behavioral
set sim_log ./project_v3/awgn_s7_25.sim/sim_1/behav/xsim/simulate.log
set channel [open $sim_log r]
set output [read $channel]
close $channel
if {[string first "PASS pipeline: 100000 consecutive pairs" $output] < 0 ||
    [regexp -nocase -line {^\s*(ERROR|FATAL):} $output]} {
    error "Behavioral simulation failed: $sim_log"
}
puts "PASS v3 project Behavioral Simulation: 100000 consecutive pairs"
close_sim
close_project
