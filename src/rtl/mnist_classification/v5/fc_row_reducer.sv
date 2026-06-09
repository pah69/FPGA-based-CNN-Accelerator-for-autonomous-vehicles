`timescale 1ns / 1ps

// FC-specific row reducer for block_size=1 workloads.
//
// It replaces the generic psum_packer + accumulator_array path for FC1:
// one launch token starts one tile capture, raw MXU psums are collected until
// all SIZE lanes arrive, then that vector is accumulated directly into a
// single output row.
module fc_row_reducer #(
    parameter int SIZE             = 4,
    parameter int LOCAL_PSUM_WIDTH = 18,
    parameter int ACC_WIDTH        = 32,
    parameter int DEPTH            = 16,
    parameter int ADDR_WIDTH       = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int NUM_TILES        = 128,
    parameter int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic clear_all_i,
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input logic row_clear_i,
    input logic [ADDR_WIDTH-1:0] row_clear_addr_i,

    input logic capture_en_i,
    input logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input logic [SIZE-1:0] psum_valid_i,

    input logic read_en_i,
    input logic [ADDR_WIDTH-1:0] read_addr_i,

    output logic busy_o,
    output logic write_active_o,
    output logic signed [(ACC_WIDTH*SIZE)-1:0] read_data_flatten_o,
    output logic read_valid_o,
    output logic row_done_o,
    output logic [ADDR_WIDTH-1:0] row_done_addr_o,
    output logic [DEPTH-1:0] row_ready_o
);

  localparam logic signed [ACC_WIDTH-1:0] ACC_MAX_VALUE = {1'b0, {(ACC_WIDTH - 1) {1'b1}}};
  localparam logic signed [ACC_WIDTH-1:0] ACC_MIN_VALUE = {1'b1, {(ACC_WIDTH - 1) {1'b0}}};

  logic signed [ACC_WIDTH-1:0] accum_q[0:SIZE-1];
  logic [SIZE-1:0] lane_seen_q;
  logic signed [LOCAL_PSUM_WIDTH-1:0] lane_data_q[0:SIZE-1];
  logic tile_active_q;
  logic [TILE_COUNT_WIDTH-1:0] tile_count_q;
  logic [DEPTH-1:0] row_ready_q;

  logic [TILE_COUNT_WIDTH-1:0] tile_limit_w;
  logic [TILE_COUNT_WIDTH-1:0] last_tile_count_w;
  logic [SIZE-1:0] lane_seen_next_w;
  logic tile_complete_w;

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

  function automatic logic signed [ACC_WIDTH-1:0] sat_add(
      input logic signed [ACC_WIDTH-1:0] acc_value_i,
      input logic signed [ACC_WIDTH-1:0] add_value_i
  );
    logic signed [ACC_WIDTH:0] sum_full;
    logic add_overflow;
    begin
      sum_full = {acc_value_i[ACC_WIDTH-1], acc_value_i} + {add_value_i[ACC_WIDTH-1], add_value_i};
      add_overflow = ~(acc_value_i[ACC_WIDTH-1] ^ add_value_i[ACC_WIDTH-1])
                  &&  (acc_value_i[ACC_WIDTH-1] ^ sum_full[ACC_WIDTH-1]);

      sat_add = add_overflow
              ? (acc_value_i[ACC_WIDTH-1] ? ACC_MIN_VALUE : ACC_MAX_VALUE)
              : sum_full[ACC_WIDTH-1:0];
    end
  endfunction

  assign tile_limit_w = clamp_tile_count(num_tiles_i);
  assign last_tile_count_w = tile_limit_w - TILE_COUNT_WIDTH'(1);

  always_comb begin
    lane_seen_next_w = lane_seen_q;
    if (tile_active_q) begin
      for (int lane = 0; lane < SIZE; lane++) begin
        if (psum_valid_i[lane]) begin
          lane_seen_next_w[lane] = 1'b1;
        end
      end
    end
  end

  assign tile_complete_w = tile_active_q && (&lane_seen_next_w);
  assign busy_o = tile_active_q;
  assign write_active_o = |psum_valid_i;
  assign row_ready_o = row_ready_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_data_flatten_o <= '0;
      read_valid_o <= 1'b0;
      row_done_o <= 1'b0;
      row_done_addr_o <= '0;
      tile_active_q <= 1'b0;
      lane_seen_q <= '0;
      tile_count_q <= '0;
      row_ready_q <= '0;

      for (int lane = 0; lane < SIZE; lane++) begin
        accum_q[lane] <= '0;
        lane_data_q[lane] <= '0;
      end
    end else if (clear_all_i) begin
      read_data_flatten_o <= '0;
      read_valid_o <= 1'b0;
      row_done_o <= 1'b0;
      row_done_addr_o <= '0;
      tile_active_q <= 1'b0;
      lane_seen_q <= '0;
      tile_count_q <= '0;
      row_ready_q <= '0;

      for (int lane = 0; lane < SIZE; lane++) begin
        accum_q[lane] <= '0;
        lane_data_q[lane] <= '0;
      end
    end else begin
      read_valid_o <= 1'b0;
      row_done_o <= 1'b0;

      if (row_clear_i && (row_clear_addr_i == '0)) begin
        tile_active_q <= 1'b0;
        lane_seen_q <= '0;
        tile_count_q <= '0;
        row_ready_q[0] <= 1'b0;
        for (int lane = 0; lane < SIZE; lane++) begin
          accum_q[lane] <= '0;
          lane_data_q[lane] <= '0;
        end
      end

      if (capture_en_i) begin
        tile_active_q <= 1'b1;
        lane_seen_q <= '0;
        for (int lane = 0; lane < SIZE; lane++) begin
          lane_data_q[lane] <= '0;
        end
      end

      if (tile_active_q) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          logic signed [LOCAL_PSUM_WIDTH-1:0] psum_lane_w;
          psum_lane_w = psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
          if (psum_valid_i[lane]) begin
            lane_data_q[lane] <= psum_lane_w;
            lane_seen_q[lane] <= 1'b1;
          end
        end

        if (tile_complete_w && (tile_count_q < tile_limit_w)) begin
          for (int lane = 0; lane < SIZE; lane++) begin
            logic signed [LOCAL_PSUM_WIDTH-1:0] psum_lane_w;
            logic signed [ACC_WIDTH-1:0] psum_ext_lane_w;

            psum_lane_w = psum_valid_i[lane]
                ? psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH]
                : lane_data_q[lane];
            psum_ext_lane_w = {
              {(ACC_WIDTH - LOCAL_PSUM_WIDTH) {psum_lane_w[LOCAL_PSUM_WIDTH-1]}},
              psum_lane_w
            };

            accum_q[lane] <= sat_add(accum_q[lane], psum_ext_lane_w);
          end

          tile_count_q <= tile_count_q + TILE_COUNT_WIDTH'(1);
          tile_active_q <= 1'b0;
          lane_seen_q <= '0;

          if (tile_count_q == last_tile_count_w) begin
            row_ready_q <= '0;
            row_ready_q[0] <= 1'b1;
            row_done_o <= 1'b1;
            row_done_addr_o <= '0;
          end
        end
      end

      if (read_en_i && row_ready_q[read_addr_i]) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          read_data_flatten_o[(lane*ACC_WIDTH)+:ACC_WIDTH] <= accum_q[lane];
        end
        read_valid_o <= 1'b1;
      end
    end
  end

endmodule : fc_row_reducer
