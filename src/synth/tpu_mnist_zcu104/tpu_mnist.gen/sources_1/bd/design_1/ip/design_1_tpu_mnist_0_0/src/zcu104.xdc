# ZCU104 constraints for the packaged TPU MNIST IP inside a block design.
#
# This IP is connected to the Zynq UltraScale+ PS through AXI SmartConnect in
# the Vivado block design. The AXI-Lite clock/reset and all AXI signals are
# internal BD nets, not top-level package pins.
#
# Do not constrain s_axi_* ports here. When this IP is packaged and placed in a
# block design, Vivado can present those interface pins as internal pins instead
# of top-level input/output ports. Applying direct-top set_input_delay,
# set_output_delay, or create_clock constraints here causes constraint warnings.
#
# Timing is driven by the PS-generated PL clock constraint, for example:
#   create_clock -name clk_pl_0 -period 10 [get_pins "PS8_i/PLCLK[0]"]
#
# Keep the PS FCLK0 frequency consistent with the software TPU_PL_CLOCK_HZ.
