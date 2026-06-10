`timescale 1ns / 1ps

// Correctness-first signed INT8 GlobalAveragePooling for CHW feature maps.
//
// Arithmetic matches Python reference:
//   round(sum / (H*W)) away from zero at the half divisor, then clamp to INT8.
module animals10_gap_i8 #(
    parameter int IN_C = 128,
    parameter int IN_H = 8,
    parameter int IN_W = 8,
    parameter int INPUT_ADDR_WIDTH = 13,
    parameter int OUTPUT_ADDR_WIDTH = 7
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

  localparam int INPUT_COUNT = IN_C * IN_H * IN_W;
  localparam int SPATIAL = IN_H * IN_W;

  logic signed [7:0] input_mem[0:INPUT_COUNT-1];
  int output_q;

  function automatic int input_idx(input int c, input int spatial);
    begin
      input_idx = (c * SPATIAL) + spatial;
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

  function automatic logic signed [7:0] gap_value(input int channel);
    longint signed sum;
    longint signed rounded;
    int signed clipped;
    begin
      sum = 64'sd0;
      for (int spatial = 0; spatial < SPATIAL; spatial++) begin
        sum += longint'(input_mem[input_idx(channel, spatial)]);
      end

      if (sum >= 0) begin
        rounded = (sum + longint'(SPATIAL / 2)) / longint'(SPATIAL);
      end else begin
        rounded = (sum - longint'(SPATIAL / 2)) / longint'(SPATIAL);
      end

      clipped = clamp_i8(rounded);
      gap_value = clipped[7:0];
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
        data_o <= gap_value(output_q);
        debug_output_count_o <= debug_output_count_o + 32'd1;

        if (output_q == IN_C - 1) begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
          output_last_o <= 1'b1;
        end else begin
          output_q <= output_q + 1;
        end
      end
    end
  end

endmodule : animals10_gap_i8
