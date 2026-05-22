# ZCU104 constraints for the current tpu_top_axi_lite design.
#
# Current synthesis/implementation top:
#   tpu_top_axi_lite
#
# This top exposes an AXI4-Lite slave interface only. The AXI signals are meant
# to connect internally to the Zynq UltraScale+ PS / AXI interconnect in a block
# design. They are not assigned to physical ZCU104 package pins in this file.
#
# For a board-level wrapper with external clock/reset/UART/LED pins, create a
# separate wrapper XDC. Do not reuse the old clk_p/clk_n/uart constraints here.

# AXI-Lite clock.
# Use 100 MHz as the default PS FCLK/AXI-Lite timing target. If the PS FCLK is
# configured differently in the block design, update this period to match:
#   100 MHz -> 10.000 ns
#   200 MHz -> 5.000 ns
#   300 MHz -> 3.333 ns
create_clock -period 10.000 -name s_axi_aclk [get_ports s_axi_aclk]
set_clock_uncertainty 0.100 [get_clocks s_axi_aclk]

# Active-low AXI reset is asynchronous in the RTL.
set_false_path -from [get_ports s_axi_aresetn]

# Timing-only constraints for direct RTL-top analysis.
# If tpu_top_axi_lite is connected inside IP Integrator, these ports become
# internal nets and the BD/PS clocking constraints should drive timing.
set_input_delay -clock [get_clocks s_axi_aclk] 1.000 [get_ports {
  s_axi_awaddr[*]
  s_axi_awvalid
  s_axi_wdata[*]
  s_axi_wstrb[*]
  s_axi_wvalid
  s_axi_bready
  s_axi_araddr[*]
  s_axi_arvalid
  s_axi_rready
}]

set_output_delay -clock [get_clocks s_axi_aclk] 1.000 [get_ports {
  s_axi_awready
  s_axi_wready
  s_axi_bresp[*]
  s_axi_bvalid
  s_axi_arready
  s_axi_rdata[*]
  s_axi_rresp[*]
  s_axi_rvalid
}]

# No PACKAGE_PIN/IOSTANDARD constraints are intentionally applied here.
# For bitstream generation on ZCU104, integrate this AXI-Lite slave behind the
# PS/AXI interconnect or create a board-level wrapper with real external pins.
