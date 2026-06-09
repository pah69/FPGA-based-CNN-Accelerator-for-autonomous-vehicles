transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xilinx_vip
vlib riviera/xpm
vlib riviera/axi_infrastructure_v1_1_0
vlib riviera/axi_vip_v1_1_22
vlib riviera/zynq_ultra_ps_e_vip_v1_0_22
vlib riviera/xil_defaultlib
vlib riviera/proc_sys_reset_v5_0_17
vlib riviera/smartconnect_v1_0
vlib riviera/axi_register_slice_v2_1_36

vmap xilinx_vip riviera/xilinx_vip
vmap xpm riviera/xpm
vmap axi_infrastructure_v1_1_0 riviera/axi_infrastructure_v1_1_0
vmap axi_vip_v1_1_22 riviera/axi_vip_v1_1_22
vmap zynq_ultra_ps_e_vip_v1_0_22 riviera/zynq_ultra_ps_e_vip_v1_0_22
vmap xil_defaultlib riviera/xil_defaultlib
vmap proc_sys_reset_v5_0_17 riviera/proc_sys_reset_v5_0_17
vmap smartconnect_v1_0 riviera/smartconnect_v1_0
vmap axi_register_slice_v2_1_36 riviera/axi_register_slice_v2_1_36

vlog -work xilinx_vip  -incr "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"/home/pah/tools/Xilinx_20252/2025.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axi_infrastructure_v1_1_0  -incr -v2k5 "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_vip_v1_1_22  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/b16a/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work zynq_ultra_ps_e_vip_v1_0_22  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl/zynq_ultra_ps_e_vip_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_zynq_ultra_ps_e_0_0/sim/design_1_zynq_ultra_ps_e_0_0_vip_wrapper.v" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/sim/bd_afc3.v" \

vcom -work proc_sys_reset_v5_0_17 -93  -incr \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/9438/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -93  -incr \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_1/sim/bd_afc3_psr_aclk_0.vhd" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/sc_util_v1_0_vl_rfs.sv" \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/3d9a/hdl/sc_mmu_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_2/sim/bd_afc3_s00mmu_0.sv" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/7785/hdl/sc_transaction_regulator_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_3/sim/bd_afc3_s00tr_0.sv" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/3051/hdl/sc_si_converter_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_4/sim/bd_afc3_s00sic_0.sv" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/852f/hdl/sc_axi2sc_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_5/sim/bd_afc3_s00a2s_0.sv" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/sc_node_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_6/sim/bd_afc3_sarn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_7/sim/bd_afc3_srn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_8/sim/bd_afc3_sawn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_9/sim/bd_afc3_swn_0.sv" \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_10/sim/bd_afc3_sbn_0.sv" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/fca9/hdl/sc_sc2axi_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_11/sim/bd_afc3_m00s2a_0.sv" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/e44a/hdl/sc_exit_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/bd_0/ip/ip_12/sim/bd_afc3_m00e_0.sv" \

vcom -work smartconnect_v1_0 -93  -incr \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/cb42/hdl/sc_ultralite_v1_0_rfs.vhd" \

vlog -work smartconnect_v1_0  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/cb42/hdl/sc_ultralite_v1_0_rfs.sv" \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/0848/hdl/sc_switchboard_v1_0_vl_rfs.sv" \

vlog -work axi_register_slice_v2_1_36  -incr -v2k5 "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/bc4b/hdl/axi_register_slice_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ip/design_1_axi_smc_0/sim/design_1_axi_smc_0.sv" \

vcom -work xil_defaultlib -93  -incr \
"../../../bd/design_1/ip/design_1_rst_ps8_0_100M_0/sim/design_1_rst_ps8_0_100M_0.vhd" \

vlog -work xil_defaultlib  -incr "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/ipshared/c604/src/accumulator_array_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/act_skew_buffer.sv" \
"../../../bd/design_1/ipshared/c604/src/activation_array_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/bias_requantize_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/bias_rom.sv" \
"../../../bd/design_1/ipshared/c604/src/conv_fc_address_generator.sv" \
"../../../bd/design_1/ipshared/c604/src/fifo.sv" \
"../../../bd/design_1/ipshared/c604/src/layer_descriptor_pkg.sv" \
"../../../bd/design_1/ipshared/c604/src/layer_descriptor_rom.sv" \
"../../../bd/design_1/ipshared/c604/src/maxpool2d_unit.sv" \
"../../../bd/design_1/ipshared/c604/src/multiplier.sv" \
"../../../bd/design_1/ipshared/c604/src/mxu_2x2.sv" \
"../../../bd/design_1/ipshared/c604/src/normalizer_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/pe.sv" \
"../../../bd/design_1/ipshared/c604/src/pooling_unit_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/post_process_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/psum_packer_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/requant_mult_rom.sv" \
"../../../bd/design_1/ipshared/c604/src/requant_shift_rom.sv" \
"../../../bd/design_1/ipshared/c604/src/tpu_controller_rom_kloop.sv" \
"../../../bd/design_1/ipshared/c604/src/tpu_controller_rom_layer.sv" \
"../../../bd/design_1/ipshared/c604/src/tpu_datapath_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/tpu_top.sv" \
"../../../bd/design_1/ipshared/c604/src/unified_buffer.sv" \
"../../../bd/design_1/ipshared/c604/src/vector_processing_unit_v2.sv" \
"../../../bd/design_1/ipshared/c604/src/weight_rom.sv" \
"../../../bd/design_1/ipshared/c604/src/wgt_fetcher_2x2.sv" \
"../../../bd/design_1/ipshared/c604/src/ws_sa_2x2.sv" \
"../../../bd/design_1/ipshared/c604/src/tpu_top_axi_lite.sv" \
"../../../bd/design_1/ipshared/c604/02b9/tpu_controller_rom_kloop.sv" \
"../../../bd/design_1/ipshared/c604/02b9/tpu_controller_rom_layer.sv" \
"../../../bd/design_1/ipshared/c604/02b9/tpu_top.sv" \
"../../../bd/design_1/ipshared/c604/02b9/tpu_top_axi_lite.sv" \
"../../../bd/design_1/ip/design_1_tpu_mnist_ip_0_0/sim/design_1_tpu_mnist_ip_0_0.sv" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/ec67/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/a0fe/hdl" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/f0b6/hdl/verilog" "+incdir+../../../../tpu_mnist.gen/sources_1/bd/design_1/ipshared/00fe/hdl/verilog" "+incdir+../../../../../../../../../tools/Xilinx_20252/2025.2/data/rsb/busdef" "+incdir+/home/pah/tools/Xilinx_20252/2025.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l axi_vip_v1_1_22 -l zynq_ultra_ps_e_vip_v1_0_22 -l xil_defaultlib -l proc_sys_reset_v5_0_17 -l smartconnect_v1_0 -l axi_register_slice_v2_1_36 \
"../../../bd/design_1/sim/design_1.v" \

vlog -work xil_defaultlib \
"glbl.v"

