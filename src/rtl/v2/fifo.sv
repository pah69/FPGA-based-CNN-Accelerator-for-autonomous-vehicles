`timescale 1ns / 1ps

module fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int COUNT_WIDTH = (DEPTH > 0) ? $clog2(DEPTH + 1) : 1
) (
    input logic clk_i,
    input logic rst_n_i,

    input  logic [WIDTH-1:0] wdata_i,
    input  logic             wr_en_i,
    output logic             full_o,

    output logic [WIDTH-1:0] rdata_o,
    input  logic             rd_en_i,
    output logic             empty_o,
    output logic [COUNT_WIDTH-1:0] count_o
);
  timeunit 1ns;
  timeprecision 100ps;

  localparam int PTR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  initial begin : parameter_check
    assert (DEPTH > 0) else $error("FIFO DEPTH must be greater than zero");
    assert ((DEPTH & (DEPTH - 1)) == 0) else $error("FIFO DEPTH must be a power of two");
  end

  logic [PTR_WIDTH-1:0] wr_ptr_q;
  logic [PTR_WIDTH-1:0] rd_ptr_q;
  logic [COUNT_WIDTH-1:0] count_q;
  logic [WIDTH-1:0] mem[0:DEPTH-1];

  logic wr_fire;
  logic rd_fire;

  assign empty_o = (count_q == '0);
  assign full_o  = (count_q == COUNT_WIDTH'(DEPTH));
  assign count_o = count_q;

  assign rd_fire = rd_en_i && !empty_o;
  assign wr_fire = wr_en_i && (!full_o || rd_fire);

  function automatic logic [PTR_WIDTH-1:0] next_ptr(input logic [PTR_WIDTH-1:0] ptr_i);
    if (DEPTH == 1) begin
      next_ptr = '0;
    end else if (ptr_i == PTR_WIDTH'(DEPTH - 1)) begin
      next_ptr = '0;
    end else begin
      next_ptr = ptr_i + PTR_WIDTH'(1);
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q  <= '0;
      rdata_o  <= '0;
    end else begin
      if (wr_fire) begin
        mem[wr_ptr_q] <= wdata_i;
        wr_ptr_q      <= next_ptr(wr_ptr_q);
      end

      if (rd_fire) begin
        rdata_o  <= mem[rd_ptr_q];
        rd_ptr_q <= next_ptr(rd_ptr_q);
      end

      unique case ({wr_fire, rd_fire})
        2'b10: count_q <= count_q + COUNT_WIDTH'(1);
        2'b01: count_q <= count_q - COUNT_WIDTH'(1);
        default: count_q <= count_q;
      endcase
    end
  end

endmodule : fifo
