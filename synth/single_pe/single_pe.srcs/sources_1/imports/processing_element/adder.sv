////////////////////////////////////////////////////////////////////////////////
// Company: <Company Name>
// Engineer: Anh Ho Pham
//
// Create Date: 03/03/2026
// Design Name: MAC_unit
// Module Name: adder
// Target Device: ZCU104
// Tool versions: Vivado 2025.2
// Description:
//    <Description here>
// Dependencies:
//    <Dependencies here>
// Revision:
//    <Code_revision_information>
// Additional Comments:
//    <Additional_comments>
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
module adder #(
    parameter DATA_WIDTH = 17
) (
    input  logic signed [DATA_WIDTH*2:0] a_i,
    input  logic signed [DATA_WIDTH*2:0] b_i,
    output logic signed [DATA_WIDTH*2:0] sum
);
  assign sum = a_i + b_i;
endmodule


