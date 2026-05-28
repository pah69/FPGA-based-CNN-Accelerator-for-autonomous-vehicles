# ZCU104 constraints for the TPU MNIST block-design project.
#
# Current Vivado project:
#   src/synth/tpu_mnist_zcu104/tpu_mnist.xpr
#
# Current top:
#   design_1_wrapper
#
# The wrapper has no external RTL IO ports. The Zynq UltraScale+ PS, AXI
# interconnect, reset block, and TPU AXI-Lite slave are all connected inside
# the block design. Because of that, this file intentionally does not assign
# PACKAGE_PIN/IOSTANDARD constraints and does not constrain s_axi_* ports.
#
# Timing source:
#   The ZynqMP PS generated XDC creates the PL clock constraint:
#     create_clock -name clk_pl_0 -period 10 [get_pins "PS8_i/PLCLK[0]"]
#
# Keep the PS FCLK0 frequency in the block design consistent with the software
# constant TPU_PL_CLOCK_HZ. The current software benchmark assumes:
#   100 MHz -> 10.000 ns
#
# If you synthesize tpu_top_axi_lite directly instead of through the block
# design, use a separate direct-top XDC with create_clock on s_axi_aclk.
