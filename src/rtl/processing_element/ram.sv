
`timescale 1ns / 1ps

module ram #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 17,
    parameter DEPTH      = 16
) (
    input  logic                  clk,
    input  logic                  cs,       // Chip Select (RAM Enable)
    input  logic                  we,       // Write Enable
    input  logic [ADDR_WIDTH-1:0] addr,     // Shared Address bus
    input  logic [DATA_WIDTH-1:0] wr_data,  // Dedicated Write Data In
    output logic [DATA_WIDTH-1:0] rd_data   // Dedicated Read Data Out
);

  // Memory array declaration
  logic [DATA_WIDTH-1:0] mem[0:DEPTH-1];

  // Memory initialization 
  initial begin
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = '0;
    end
  end

  // Standard BRAM inferred template
  always_ff @(posedge clk) begin
    if (cs) begin
      // Write Operation
      if (we) begin
        mem[addr] <= wr_data;
      end
      // Read Operation
      // By placing this inside the 'cs' block, rd_data acts as a registered output.
      rd_data <= mem[addr];
    end
  end

endmodule
