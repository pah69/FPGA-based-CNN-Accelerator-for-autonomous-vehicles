`timescale 1ns / 1ps

// Legacy single-lane accumulator used by the local MXU path.
module output_accumulator_v2 #(
    parameter int LOCAL_PSUM_WIDTH = 18,
    parameter int ACC_WIDTH        = 32,
    parameter int NUM_TILES        = 2,
    parameter int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1
) (
    input logic clk,
    input logic rst_n,
    input logic clear_i,

    input logic work_i,
    // Runtime K-tile count for the current output row group.
    // Keep this stable from work_i start until done_o.
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input logic signed [LOCAL_PSUM_WIDTH-1:0] psum_i,
    input logic                               psum_valid_i,

    output logic signed [ACC_WIDTH-1:0] result_o,
    output logic                        done_o
);

  localparam logic signed [ACC_WIDTH-1:0] ACC_MAX_VALUE = {1'b0, {(ACC_WIDTH - 1) {1'b1}}};
  localparam logic signed [ACC_WIDTH-1:0] ACC_MIN_VALUE = {1'b1, {(ACC_WIDTH - 1) {1'b0}}};

  logic                            work_d;
  logic                            running_q;
  logic [TILE_COUNT_WIDTH-1:0]     count_q;
  logic [TILE_COUNT_WIDTH-1:0]     target_count_q;
  logic signed [ACC_WIDTH-1:0]     acc_q;
  logic signed [ACC_WIDTH-1:0]     psum_ext;
  logic signed [ACC_WIDTH:0]       acc_sum_full;
  logic signed [ACC_WIDTH-1:0]     acc_sum_sat;
  logic                            add_overflow;

  // In the TPU controller, work_i is a launch pulse for each streamed
  // activation vector. For FC local accumulation we only want to arm once per
  // output tile, then ignore subsequent launch pulses until the current
  // reduction completes.
  wire                             work_start = work_i && !work_d && !running_q;

  assign psum_ext = {{(ACC_WIDTH - LOCAL_PSUM_WIDTH) {psum_i[LOCAL_PSUM_WIDTH-1]}}, psum_i};
  assign acc_sum_full = {acc_q[ACC_WIDTH-1], acc_q} + {psum_ext[ACC_WIDTH-1], psum_ext};
  assign add_overflow = ~(acc_q[ACC_WIDTH-1] ^ psum_ext[ACC_WIDTH-1])
                      &&  (acc_q[ACC_WIDTH-1] ^ acc_sum_full[ACC_WIDTH-1]);

  assign acc_sum_sat = add_overflow
                     ? (acc_q[ACC_WIDTH-1] ? ACC_MIN_VALUE : ACC_MAX_VALUE)
                     : acc_sum_full[ACC_WIDTH-1:0];

  // Expose the just-computed sum combinationally so downstream logic can latch
  // the final reduced value in the same cycle that done_o pulses.
  assign result_o = (running_q && psum_valid_i && (count_q < target_count_q)) ? acc_sum_sat : acc_q;

  function automatic logic [TILE_COUNT_WIDTH-1:0] clamp_tile_count(
      input logic [TILE_COUNT_WIDTH-1:0] tile_count_i
  );
    logic [TILE_COUNT_WIDTH-1:0] max_tiles;
    begin
      max_tiles = TILE_COUNT_WIDTH'(NUM_TILES);
      if (tile_count_i == '0) begin
        clamp_tile_count = max_tiles;
      end else if (tile_count_i > max_tiles) begin
        clamp_tile_count = max_tiles;
      end else begin
        clamp_tile_count = tile_count_i;
      end
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      work_d <= 1'b0;
    end else if (clear_i) begin
      work_d <= 1'b0;
    end else begin
      work_d <= work_i;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_q          <= '0;
      count_q        <= '0;
      target_count_q <= TILE_COUNT_WIDTH'(NUM_TILES);
      running_q      <= 1'b0;
      done_o         <= 1'b0;
    end else if (clear_i) begin
      acc_q          <= '0;
      count_q        <= '0;
      target_count_q <= TILE_COUNT_WIDTH'(NUM_TILES);
      running_q      <= 1'b0;
      done_o         <= 1'b0;
    end else if (work_start) begin
      acc_q          <= '0;
      count_q        <= '0;
      target_count_q <= clamp_tile_count(num_tiles_i);
      running_q      <= 1'b1;
      done_o         <= 1'b0;
    end else if (running_q && psum_valid_i && (count_q < target_count_q)) begin
      acc_q   <= acc_sum_sat;
      count_q <= count_q + 1'b1;

      if (count_q == (target_count_q - TILE_COUNT_WIDTH'(1))) begin
        running_q <= 1'b0;
        done_o    <= 1'b1;
      end
    end
  end

endmodule : output_accumulator_v2
