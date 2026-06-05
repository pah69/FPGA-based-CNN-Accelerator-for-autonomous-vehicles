`timescale 1ns / 1ps

// Row-addressed accumulator memory.
module accumulator_array #(
    parameter int SIZE             = 2,
    parameter int LOCAL_PSUM_WIDTH = 18,
    parameter int ACC_WIDTH        = 32,
    parameter int DEPTH            = 16,
    parameter int ADDR_WIDTH       = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int NUM_TILES        = 2,
    parameter int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic clear_all_i,
    // Runtime K-tile count for the active workload.
    // Zero-padded tail tiles still count as real tiles here.
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input logic row_clear_i,
    input logic [ADDR_WIDTH-1:0] row_clear_addr_i,

    input logic                                      write_en_i,
    input logic        [             ADDR_WIDTH-1:0] write_addr_i,
    input logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input logic        [                   SIZE-1:0] psum_valid_i,

    input  logic                               read_en_i,
    input  logic        [      ADDR_WIDTH-1:0] read_addr_i,
    output logic signed [(ACC_WIDTH*SIZE)-1:0] read_data_flatten_o,
    output logic                               read_valid_o,

    output logic                  row_done_o,
    output logic [ADDR_WIDTH-1:0] row_done_addr_o,
    output logic [     DEPTH-1:0] row_ready_o
);
  localparam logic signed [ACC_WIDTH-1:0] ACC_MAX_VALUE = {1'b0, {(ACC_WIDTH - 1) {1'b1}}};
  localparam logic signed [ACC_WIDTH-1:0] ACC_MIN_VALUE = {1'b1, {(ACC_WIDTH - 1) {1'b0}}};

  logic signed [       ACC_WIDTH-1:0] acc_mem_q          [0:DEPTH-1] [0:SIZE-1];
  logic        [TILE_COUNT_WIDTH-1:0] tile_count_q       [0:DEPTH-1];
  logic        [           DEPTH-1:0] row_ready_q;
  logic        [TILE_COUNT_WIDTH-1:0] tile_count_limit_w;
  logic        [TILE_COUNT_WIDTH-1:0] last_tile_count_w;

  function automatic logic signed [ACC_WIDTH-1:0] sat_add(
      input logic signed [ACC_WIDTH-1:0] acc_value_i,
      input logic signed [ACC_WIDTH-1:0] add_value_i);
    logic signed [ACC_WIDTH:0] sum_full;
    logic                      add_overflow;
    begin
      sum_full = {acc_value_i[ACC_WIDTH-1], acc_value_i} + {add_value_i[ACC_WIDTH-1], add_value_i};
      add_overflow = ~(acc_value_i[ACC_WIDTH-1] ^ add_value_i[ACC_WIDTH-1])
                  &&  (acc_value_i[ACC_WIDTH-1] ^ sum_full[ACC_WIDTH-1]);

      sat_add = add_overflow
              ? (acc_value_i[ACC_WIDTH-1] ? ACC_MIN_VALUE : ACC_MAX_VALUE)
              : sum_full[ACC_WIDTH-1:0];
    end
  endfunction

  function automatic logic [TILE_COUNT_WIDTH-1:0] clamp_tile_count(
      input logic [TILE_COUNT_WIDTH-1:0] tile_count_i);
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

  assign tile_count_limit_w = clamp_tile_count(num_tiles_i);
  assign last_tile_count_w  = tile_count_limit_w - TILE_COUNT_WIDTH'(1);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_data_flatten_o <= '0;
      read_valid_o        <= 1'b0;
      row_done_o          <= 1'b0;
      row_done_addr_o     <= '0;
      row_ready_q         <= '0;

      for (int row = 0; row < DEPTH; row++) begin
        tile_count_q[row] <= '0;
        for (int lane = 0; lane < SIZE; lane++) begin
          acc_mem_q[row][lane] <= '0;
        end
      end
    end else if (clear_all_i) begin
      read_data_flatten_o <= '0;
      read_valid_o        <= 1'b0;
      row_done_o          <= 1'b0;
      row_done_addr_o     <= '0;
      row_ready_q         <= '0;

      for (int row = 0; row < DEPTH; row++) begin
        tile_count_q[row] <= '0;
        for (int lane = 0; lane < SIZE; lane++) begin
          acc_mem_q[row][lane] <= '0;
        end
      end
    end else begin
      read_valid_o <= 1'b0;
      row_done_o   <= 1'b0;

      if (row_clear_i) begin
        tile_count_q[row_clear_addr_i] <= '0;
        row_ready_q[row_clear_addr_i]  <= 1'b0;
        for (int lane = 0; lane < SIZE; lane++) begin
          acc_mem_q[row_clear_addr_i][lane] <= '0;
        end
      end

      if (write_en_i && (|psum_valid_i) && (tile_count_q[write_addr_i] < tile_count_limit_w)) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          logic signed [ACC_WIDTH-1:0] psum_ext_lane;

          psum_ext_lane = {
            {(ACC_WIDTH - LOCAL_PSUM_WIDTH) {psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+LOCAL_PSUM_WIDTH-1]}},
            psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH]
          };

          if (psum_valid_i[lane]) begin
            acc_mem_q[write_addr_i][lane] <= sat_add(acc_mem_q[write_addr_i][lane], psum_ext_lane);
          end
        end

        tile_count_q[write_addr_i] <= tile_count_q[write_addr_i] + 1'b1;

        if (tile_count_q[write_addr_i] == last_tile_count_w) begin
          row_ready_q[write_addr_i] <= 1'b1;
          row_done_o                <= 1'b1;
          row_done_addr_o           <= write_addr_i;
        end
      end

      if (read_en_i && row_ready_q[read_addr_i]) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          read_data_flatten_o[(lane*ACC_WIDTH)+:ACC_WIDTH] <= acc_mem_q[read_addr_i][lane];
        end
        read_valid_o <= 1'b1;
      end
    end
  end

  assign row_ready_o = row_ready_q;

endmodule : accumulator_array_v2
