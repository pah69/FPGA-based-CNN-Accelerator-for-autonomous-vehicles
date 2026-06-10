`timescale 1ns / 1ps

// Correctness-first signed INT8 2x2 MaxPool for CHW feature maps.
//
// V1 policy:
//   - input feature map is written by address before start_i
//   - one pooled output is emitted per cycle while busy
//   - output layout is CHW
module animals10_maxpool2x2_i8 #(
    parameter int IN_C = 32,
    parameter int IN_H = 64,
    parameter int IN_W = 64,
    parameter int POOL = 2,
    parameter int INPUT_ADDR_WIDTH = 17,
    parameter int OUTPUT_ADDR_WIDTH = 15
) (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [INPUT_ADDR_WIDTH-1:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [OUTPUT_ADDR_WIDTH-1:0] output_index_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_cycle_count_o,
    output logic [31:0] debug_output_count_o
);

  localparam int OUT_H = IN_H / POOL;
  localparam int OUT_W = IN_W / POOL;
  localparam int INPUT_COUNT = IN_C * IN_H * IN_W;
  localparam int OUT_SPATIAL = OUT_H * OUT_W;
  localparam int OUT_COUNT = IN_C * OUT_SPATIAL;

  initial begin : parameter_check
    assert (POOL == 2) else $error("animals10_maxpool2x2_i8 supports POOL=2 only");
    assert ((IN_H % POOL) == 0) else $error("IN_H must be divisible by POOL");
    assert ((IN_W % POOL) == 0) else $error("IN_W must be divisible by POOL");
  end

  logic signed [7:0] input_mem[0:INPUT_COUNT-1];
  int output_q;

  function automatic int input_idx(input int c, input int y, input int x);
    begin
      input_idx = (c * IN_H * IN_W) + (y * IN_W) + x;
    end
  endfunction

  function automatic logic signed [7:0] max4_i8(
      input logic signed [7:0] a,
      input logic signed [7:0] b,
      input logic signed [7:0] c,
      input logic signed [7:0] d
  );
    logic signed [7:0] ab;
    logic signed [7:0] cd;
    begin
      ab = (a > b) ? a : b;
      cd = (c > d) ? c : d;
      max4_i8 = (ab > cd) ? ab : cd;
    end
  endfunction

  function automatic logic signed [7:0] pool_value(input int out_index);
    int channel;
    int rem;
    int oy;
    int ox;
    int in_y;
    int in_x;
    begin
      channel = out_index / OUT_SPATIAL;
      rem = out_index - (channel * OUT_SPATIAL);
      oy = rem / OUT_W;
      ox = rem - (oy * OUT_W);
      in_y = oy * POOL;
      in_x = ox * POOL;

      pool_value = max4_i8(
          input_mem[input_idx(channel, in_y, in_x)],
          input_mem[input_idx(channel, in_y, in_x + 1)],
          input_mem[input_idx(channel, in_y + 1, in_x)],
          input_mem[input_idx(channel, in_y + 1, in_x + 1)]
      );
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_o <= 1'b0;
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;
      output_index_o <= '0;
      data_o <= '0;
      output_q <= 0;
      debug_cycle_count_o <= '0;
      debug_output_count_o <= '0;
    end else begin
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;

      if (input_we_i) begin
        input_mem[input_addr_i] <= input_data_i;
      end

      if (busy_o) begin
        debug_cycle_count_o <= debug_cycle_count_o + 32'd1;
      end

      if (start_i && !busy_o) begin
        busy_o <= 1'b1;
        output_q <= 0;
        debug_cycle_count_o <= '0;
        debug_output_count_o <= '0;
      end else if (busy_o) begin
        output_valid_o <= 1'b1;
        output_index_o <= OUTPUT_ADDR_WIDTH'(output_q);
        data_o <= pool_value(output_q);
        debug_output_count_o <= debug_output_count_o + 32'd1;

        if (output_q == OUT_COUNT - 1) begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
          output_last_o <= 1'b1;
        end else begin
          output_q <= output_q + 1;
        end
      end
    end
  end

endmodule : animals10_maxpool2x2_i8
