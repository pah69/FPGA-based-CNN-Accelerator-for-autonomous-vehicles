vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xilinx_vip
vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/axi_infrastructure_v1_1_0
vlib modelsim_lib/msim/axi_vip_v1_1_22
vlib modelsim_lib/msim/processing_system7_vip_v1_0_24
vlib modelsim_lib/msim/proc_sys_reset_v5_0_17
vlib modelsim_lib/msim/smartconnect_v1_0
vlib modelsim_lib/msim/axi_register_slice_v2_1_36

vmap xilinx_vip modelsim_lib/msim/xilinx_vip
vmap xpm modelsim_lib/msim/xpm
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap axi_infrastructure_v1_1_0 modelsim_lib/msim/axi_infrastructure_v1_1_0
vmap axi_vip_v1_1_22 modelsim_lib/msim/axi_vip_v1_1_22
vmap processing_system7_vip_v1_0_24 modelsim_lib/msim/processing_system7_vip_v1_0_24
vmap proc_sys_reset_v5_0_17 modelsim_lib/msim/proc_sys_reset_v5_0_17
vmap smartconnect_v1_0 modelsim_lib/msim/smartconnect_v1_0
vmap axi_register_slice_v2_1_36 modelsim_lib/msim/axi_register_slice_v2_1_36

vlog -work xilinx_vip -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -64 -93  \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ipshared/38af/src/accumulator_array_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/act_skew_buffer.sv" \
"../../../bd/design_1/ipshared/38af/src/activation_array_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/bias_requantize_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/bias_rom.sv" \
"../../../bd/design_1/ipshared/38af/src/conv_fc_address_generator.sv" \
"../../../bd/design_1/ipshared/38af/src/fifo.sv" \
"../../../bd/design_1/ipshared/38af/src/layer_descriptor_pkg.sv" \
"../../../bd/design_1/ipshared/38af/src/layer_descriptor_rom.sv" \
"../../../bd/design_1/ipshared/38af/src/maxpool2d_unit.sv" \
"../../../bd/design_1/ipshared/38af/src/multiplier.sv" \
"../../../bd/design_1/ipshared/38af/src/mxu_2x2.sv" \
"../../../bd/design_1/ipshared/38af/src/normalizer_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/pe.sv" \
"../../../bd/design_1/ipshared/38af/src/pooling_unit_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/post_process_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/psum_packer_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/requant_mult_rom.sv" \
"../../../bd/design_1/ipshared/38af/src/requant_shift_rom.sv" \
"../../../bd/design_1/ipshared/38af/src/tpu_controller_rom_kloop.sv" \
"../../../bd/design_1/ipshared/38af/src/tpu_controller_rom_layer.sv" \
"../../../bd/design_1/ipshared/38af/src/tpu_datapath_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/tpu_top.sv" \
"../../../bd/design_1/ipshared/38af/src/unified_buffer.sv" \
"../../../bd/design_1/ipshared/38af/src/vector_processing_unit_v2.sv" \
"../../../bd/design_1/ipshared/38af/src/weight_rom.sv" \
"../../../bd/design_1/ipshared/38af/src/wgt_fetcher_2x2.sv" \
"../../../bd/design_1/ipshared/38af/src/ws_sa_2x2.sv" \
"../../../bd/design_1/ipshared/38af/src/tpu_top_axi_lite.sv" \
"../../../bd/design_1/ip/design_1_tpu_zybo_0_0/sim/design_1_tpu_zybo_0_0.sv" \

vlog -work axi_infrastructure_v1_1_0 -64 -incr -mfcu  "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_vip_v1_1_22 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/b16a/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work processing_system7_vip_v1_0_24 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl/processing_system7_vip_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_processing_system7_0_0/sim/design_1_processing_system7_0_0.v" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/sim/bd_afc3.v" \

vcom -work proc_sys_reset_v5_0_17 -64 -93  \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9438/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -64 -93  \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_1/sim/bd_afc3_psr_aclk_0.vhd" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/sc_util_v1_0_vl_rfs.sv" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/3d9a/hdl/sc_mmu_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_2/sim/bd_afc3_s00mmu_0.sv" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/7785/hdl/sc_transaction_regulator_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_3/sim/bd_afc3_s00tr_0.sv" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/3051/hdl/sc_si_converter_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_4/sim/bd_afc3_s00sic_0.sv" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/852f/hdl/sc_axi2sc_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_5/sim/bd_afc3_s00a2s_0.sv" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/sc_node_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_6/sim/bd_afc3_sarn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_7/sim/bd_afc3_srn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_8/sim/bd_afc3_sawn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_9/sim/bd_afc3_swn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_10/sim/bd_afc3_sbn_0.sv" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/fca9/hdl/sc_sc2axi_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_11/sim/bd_afc3_m00s2a_0.sv" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/e44a/hdl/sc_exit_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_12/sim/bd_afc3_m00e_0.sv" \

vcom -work smartconnect_v1_0 -64 -93  \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/cb42/hdl/sc_ultralite_v1_0_rfs.vhd" \

vlog -work smartconnect_v1_0 -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/cb42/hdl/sc_ultralite_v1_0_rfs.sv" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/0848/hdl/sc_switchboard_v1_0_vl_rfs.sv" \

vlog -work axi_register_slice_v2_1_36 -64 -incr -mfcu  "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/bc4b/hdl/axi_register_slice_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L smartconnect_v1_0 -L axi_vip_v1_1_22 -L processing_system7_vip_v1_0_24 -L xilinx_vip "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/ip/design_1_axi_smc_0/sim/design_1_axi_smc_0.sv" \

vcom -work xil_defaultlib -64 -93  \
"../../../bd/design_1/ip/design_1_rst_ps7_0_50M_0/sim/design_1_rst_ps7_0_50M_0.vhd" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/9a25/hdl" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist_zyboz7.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" \
"../../../bd/design_1/sim/design_1.v" \

vlog -work xil_defaultlib \
"glbl.v"

