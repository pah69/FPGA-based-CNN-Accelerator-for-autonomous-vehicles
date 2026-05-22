set_property SRC_FILE_INFO {cfile:/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/synth/zcu104.xdc rfile:../../../../zcu104.xdc id:1} [current_design]
set_property src_info {type:XDC file:1 line:19 export:INPUT save:INPUT read:READ} [current_design]
create_clock -period 10.000 -name s_axi_aclk [get_ports s_axi_aclk]
set_property src_info {type:XDC file:1 line:20 export:INPUT save:INPUT read:READ} [current_design]
set_clock_uncertainty 0.100 [get_clocks s_axi_aclk]
set_property src_info {type:XDC file:1 line:23 export:INPUT save:INPUT read:READ} [current_design]
set_false_path -from [get_ports s_axi_aresetn]
set_property src_info {type:XDC file:1 line:28 export:INPUT save:INPUT read:READ} [current_design]
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
set_property src_info {type:XDC file:1 line:40 export:INPUT save:INPUT read:READ} [current_design]
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
