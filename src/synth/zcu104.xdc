# Copyright TU Wien
# Licensed under the Solderpad Hardware License v2.1, see LICENSE.txt for details
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1


## ZCU104 board constraints
##
## Verified against the Vivado ZCU104 board files:
##   - board.xml
##   - part0_pins.xml
##
## Notes:
##   - The official PL board clock exposed by the AMD board files is the
##     programmable 300 MHz differential clock on AH18/AH17.
##   - The PL UART uses LVCMOS18 on C19/A20.
##   - CPU_RESET on M11 is active-high. The constraint below assumes an
##     active-high port such as `cpu_reset_i`.
##   - The current project top `ws_sa_3x3` only exposes a single-ended `clk`,
##     so this file is written for a small board wrapper rather than the raw
##     array module.


## Clock Signal: ZCU104 programmable 300 MHz differential PL clock
set_property PACKAGE_PIN AH18 [get_ports {clk_p}]
set_property PACKAGE_PIN AH17 [get_ports {clk_n}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {clk_p clk_n}]
create_clock -period 3.333 -name sysclk [get_ports {clk_p}]


## Reset: CPU_RESET pushbutton, active-high on the board
set_property PACKAGE_PIN M11 [get_ports {cpu_reset_i}]
set_property IOSTANDARD LVCMOS33 [get_ports {cpu_reset_i}]


## UART: ZCU104 PL UART through CP2108
set_property PACKAGE_PIN C19 [get_ports {uart_tx_o}]
set_property IOSTANDARD LVCMOS18 [get_ports {uart_tx_o}]
set_property PACKAGE_PIN A20 [get_ports {uart_rx_i}]
set_property IOSTANDARD LVCMOS18 [get_ports {uart_rx_i}]


## Optional user LEDs
# set_property PACKAGE_PIN D5 [get_ports {user_led_o[0]}]
# set_property PACKAGE_PIN D6 [get_ports {user_led_o[1]}]
# set_property PACKAGE_PIN A5 [get_ports {user_led_o[2]}]
# set_property PACKAGE_PIN B5 [get_ports {user_led_o[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {user_led_o[*]}]


## Optional pushbuttons
# set_property PACKAGE_PIN B4 [get_ports {user_btn_i[0]}]
# set_property PACKAGE_PIN C4 [get_ports {user_btn_i[1]}]
# set_property PACKAGE_PIN B3 [get_ports {user_btn_i[2]}]
# set_property PACKAGE_PIN C3 [get_ports {user_btn_i[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {user_btn_i[*]}]


## Optional DIP switches
# set_property PACKAGE_PIN E4 [get_ports {user_sw_i[0]}]
# set_property PACKAGE_PIN D4 [get_ports {user_sw_i[1]}]
# set_property PACKAGE_PIN F5 [get_ports {user_sw_i[2]}]
# set_property PACKAGE_PIN F4 [get_ports {user_sw_i[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {user_sw_i[*]}]
