`timescale 1ns / 1ps

// Correctness-first Animals-10 Conv1 reference engine.
//
// This is not the accelerator compute heart. The real Animals-10 accelerator
// starts from a SIZE=4 systolic array. Keep this block as an RTL reference for
// locking the RGB CHW/OIHW address contract and signed INT8 arithmetic against
// the Python golden model.
module animals10_conv1_direct #(
    parameter int IN_C = 3,
    parameter int IN_H = 64,
    parameter int IN_W = 64,
    parameter int OUT_C = 32,
    parameter int OUT_H = 64,
    parameter int OUT_W = 64,
    parameter int K_H = 3,
    parameter int K_W = 3,
    parameter int PAD = 1,
    parameter int INPUT_ADDR_WIDTH = 14,
    parameter int WEIGHT_ADDR_WIDTH = 10,
    parameter int PARAM_ADDR_WIDTH = 5,
    parameter int OUTPUT_ADDR_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [INPUT_ADDR_WIDTH-1:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [WEIGHT_ADDR_WIDTH-1:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [PARAM_ADDR_WIDTH-1:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [OUTPUT_ADDR_WIDTH-1:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o
);

  localparam int INPUT_COUNT = IN_C * IN_H * IN_W;
  localparam int WEIGHT_COUNT = OUT_C * IN_C * K_H * K_W;
  localparam int OUT_SPATIAL = OUT_H * OUT_W;
  localparam int OUT_COUNT = OUT_C * OUT_SPATIAL;

  logic signed [7:0] input_mem[0:INPUT_COUNT-1];
  logic signed [7:0] weight_mem[0:WEIGHT_COUNT-1];
  logic signed [31:0] bias_mem[0:OUT_C-1];
  logic signed [31:0] requant_mult_mem[0:OUT_C-1];
  logic signed [7:0] requant_shift_mem[0:OUT_C-1];

  logic [OUTPUT_ADDR_WIDTH-1:0] out_index_q;

  longint signed acc_w;
  logic signed [7:0] data_w;

  function automatic int input_idx(input int c, input int y, input int x);
    begin
      input_idx = (c * IN_H * IN_W) + (y * IN_W) + x;
    end
  endfunction

  function automatic int weight_idx(input int oc, input int ic, input int ky, input int kx);
    begin
      weight_idx = (((oc * IN_C + ic) * K_H + ky) * K_W + kx);
    end
  endfunction

  function automatic int signed input_value(input int c, input int y, input int x);
    begin
      if (y < 0 || y >= IN_H || x < 0 || x >= IN_W) begin
        input_value = 0;
      end else begin
        input_value = int'(input_mem[input_idx(c, y, x)]);
      end
    end
  endfunction

  function automatic longint signed round_shift_i64(input longint signed value, input int shift);
    longint signed offset;
    begin
      if (shift == 0) begin
        round_shift_i64 = value;
      end else begin
        offset = 64'sd1 <<< (shift - 1);
        if (value >= 0) begin
          round_shift_i64 = (value + offset) >>> shift;
        end else begin
          round_shift_i64 = (value - offset) >>> shift;
        end
      end
    end
  endfunction

  function automatic int signed clamp_i8(input longint signed value);
    begin
      if (value > 127) begin
        clamp_i8 = 127;
      end else if (value < -128) begin
        clamp_i8 = -128;
      end else begin
        clamp_i8 = int'(value);
      end
    end
  endfunction

  function automatic logic signed [7:0] requant_relu(
      input int oc,
      input longint signed acc
  );
    longint signed biased;
    longint signed product;
    longint signed scaled;
    int signed clipped;
    begin
      biased = acc + longint'(bias_mem[oc]);
      product = biased * longint'(requant_mult_mem[oc]);
      scaled = round_shift_i64(product, int'(requant_shift_mem[oc]));
      clipped = clamp_i8(scaled);
      if (clipped < 0) begin
        requant_relu = 8'sd0;
      end else begin
        requant_relu = clipped[7:0];
      end
    end
  endfunction

  always_comb begin
    int oc;
    int spatial;
    int oy;
    int ox;
    int in_y;
    int in_x;

    oc = int'(out_index_q) / OUT_SPATIAL;
    spatial = int'(out_index_q) - (oc * OUT_SPATIAL);
    oy = spatial / OUT_W;
    ox = spatial - (oy * OUT_W);

    acc_w = 0;
    for (int ic = 0; ic < IN_C; ic++) begin
      for (int ky = 0; ky < K_H; ky++) begin
        for (int kx = 0; kx < K_W; kx++) begin
          in_y = oy + ky - PAD;
          in_x = ox + kx - PAD;
          acc_w += longint'(input_value(ic, in_y, in_x))
                 * longint'(weight_mem[weight_idx(oc, ic, ky, kx)]);
        end
      end
    end

    data_w = requant_relu(oc, acc_w);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_o <= 1'b0;
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;
      output_index_o <= '0;
      acc_o <= '0;
      data_o <= '0;
      out_index_q <= '0;
    end else begin
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;

      if (input_we_i) begin
        input_mem[input_addr_i] <= input_data_i;
      end
      if (weight_we_i) begin
        weight_mem[weight_addr_i] <= weight_data_i;
      end
      if (param_we_i) begin
        bias_mem[param_addr_i] <= bias_data_i;
        requant_mult_mem[param_addr_i] <= requant_mult_data_i;
        requant_shift_mem[param_addr_i] <= requant_shift_data_i;
      end

      if (start_i && !busy_o) begin
        busy_o <= 1'b1;
        out_index_q <= '0;
      end else if (busy_o) begin
        output_valid_o <= 1'b1;
        output_index_o <= out_index_q;
        acc_o <= acc_w[31:0];
        data_o <= data_w;

        if (out_index_q == OUTPUT_ADDR_WIDTH'(OUT_COUNT - 1)) begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
          output_last_o <= 1'b1;
        end else begin
          out_index_q <= out_index_q + OUTPUT_ADDR_WIDTH'(1);
        end
      end
    end
  end

endmodule : animals10_conv1_direct
