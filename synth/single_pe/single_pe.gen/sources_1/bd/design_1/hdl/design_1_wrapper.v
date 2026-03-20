//Copyright 1986-2023 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2.2 (lin64) Build 3788238 Tue Feb 21 19:59:23 MST 2023
//Date        : Fri Mar 20 17:17:26 2026
//Host        : pah-PC running 64-bit Ubuntu 24.04.4 LTS
//Command     : generate_target design_1_wrapper.bd
//Design      : design_1_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module design_1_wrapper
   (clk_100MHz,
    reset);
  input clk_100MHz;
  input reset;

  wire clk_100MHz;
  wire reset;

  design_1 design_1_i
       (.clk_100MHz(clk_100MHz),
        .reset(reset));
endmodule
