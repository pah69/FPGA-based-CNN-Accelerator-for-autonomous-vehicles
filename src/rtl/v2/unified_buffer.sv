`timescale 1ns / 1ps

// Two-bank signed INT8 unified buffer for activation/output tensors.
module unified_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int BANK_DEPTH = 8192,
    parameter int ADDR_WIDTH = (BANK_DEPTH > 1) ? $clog2(BANK_DEPTH) : 1
) (
    input logic clk,
    input logic rst_n,

    input  logic                         rd_en_i,
    input  logic                         rd_bank_i,
    input  logic [      ADDR_WIDTH-1:0]  rd_addr_i,
    output logic signed [DATA_WIDTH-1:0] rd_data_o,
    output logic                         rd_valid_o,

    input logic                         wr_en_i,
    input logic                         wr_bank_i,
    input logic [      ADDR_WIDTH-1:0]  wr_addr_i,
    input logic signed [DATA_WIDTH-1:0] wr_data_i
);

  initial begin : parameter_check
    assert (BANK_DEPTH > 0) else $error("Unified buffer BANK_DEPTH must be greater than zero");
  end

  logic signed [DATA_WIDTH-1:0] bank0_mem[0:BANK_DEPTH-1];
  logic signed [DATA_WIDTH-1:0] bank1_mem[0:BANK_DEPTH-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_data_o  <= '0;
      rd_valid_o <= 1'b0;
    end else begin
      rd_valid_o <= rd_en_i;

      if (rd_en_i) begin
        rd_data_o <= rd_bank_i ? bank1_mem[rd_addr_i] : bank0_mem[rd_addr_i];
      end

      if (wr_en_i) begin
        if (wr_bank_i) begin
          bank1_mem[wr_addr_i] <= wr_data_i;
        end else begin
          bank0_mem[wr_addr_i] <= wr_data_i;
        end
      end
    end
  end

endmodule : unified_buffer
