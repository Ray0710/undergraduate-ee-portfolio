# Arty S7-25 Rev. E, xc7s25csga324-1. Official Digilent master XDC:
# https://github.com/Digilent/digilent-xdc/blob/master/Arty-S7-25-Master.xdc
# F14 is the 12 MHz clock. G15 is user button BTN0, active high.
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports CLK12MHZ]
create_clock -name sys_clk -period 83.333 -waveform {0 41.667} [get_ports CLK12MHZ]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports RESET_BTN]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
# R12: FPGA TX -> USB-UART bridge RX (official name uart_rxd_out).
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports UART_TX]
# External reset is asynchronous. All release transitions pass through reset_pipe.
set_false_path -from [get_ports RESET_BTN]
# LEDs and asynchronous UART TX have no phase-related external sampling clock.
set_false_path -to [get_ports {LED[*] UART_TX}]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property INTERNAL_VREF 0.675 [get_iobanks 34]
