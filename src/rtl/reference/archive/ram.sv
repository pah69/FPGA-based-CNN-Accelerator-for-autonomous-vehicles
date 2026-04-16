////////////////////////////////////////////////////////////////////////////////
// Company: <Company Name>
// Engineer: Anh Ho Pham
//
// Create Date: 03/03/2026
// Design Name: MAC_unit
// Module Name: multiplier
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

module ram #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 17,
    parameter DEPTH      = 16
) (
    input  logic                  clk,
    input  logic                  cs,       // Chip Select
    input  logic                  we,       // Write enable
    input  logic [ADDR_WIDTH-1:0] addr,     // Address bus
    input  logic [DATA_WIDTH-1:0] wr_data,  // write port in
    output logic [DATA_WIDTH-1:0] rd_data   // read port out 
);

  // Memory array
  logic [DATA_WIDTH-1:0] mem[0:DEPTH-1];

  // Memory initialization 
  initial begin
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = '0;
    end
  end

  // logic block
  always_ff @(posedge clk) begin
    if (cs) begin
      // Write op
      if (we) begin
        mem[addr] <= wr_data;
      end
      // Read op
      // rd_data acts as a registered output 
      rd_data <= mem[addr];
    end
  end

endmodule
