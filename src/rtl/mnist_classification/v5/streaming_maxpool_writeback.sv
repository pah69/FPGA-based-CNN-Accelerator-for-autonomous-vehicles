`timescale 1ns / 1ps

// Streaming 2x2 stride-2 max-pool writeback for channel-major conv outputs.
// The input stream must present one channel's spatial samples in monotonically
// increasing raster order, but channels may be interleaved by oc tiles.
module streaming_maxpool_writeback #(
    parameter int DATA_WIDTH      = 8,
    parameter int ADDR_WIDTH      = 13,
    parameter int DIM_WIDTH       = 16,
    parameter int MAX_CHANNELS    = 16,
    parameter int MAX_POOL_COLS   = 16,
    parameter int ADDR_CALC_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,
    input logic enable_i,

    input logic                        write_bank_i,
    input logic [ADDR_WIDTH-1:0]       output_base_addr_i,
    input logic [DIM_WIDTH-1:0]        input_h_i,
    input logic [DIM_WIDTH-1:0]        input_w_i,
    input logic [DIM_WIDTH-1:0]        output_h_i,
    input logic [DIM_WIDTH-1:0]        output_w_i,
    input logic [DIM_WIDTH-1:0]        output_ch_i,

    input logic                        stream_valid_i,
    input logic [DIM_WIDTH-1:0]        stream_channel_idx_i,
    input logic signed [DATA_WIDTH-1:0] stream_data_i,

    output logic                        ub_wr_en_o,
    output logic                        ub_wr_bank_o,
    output logic [ADDR_WIDTH-1:0]       ub_wr_addr_o,
    output logic signed [DATA_WIDTH-1:0] ub_wr_data_o
);

  logic [DIM_WIDTH-1:0] channel_row_q[0:MAX_CHANNELS-1];
  logic [DIM_WIDTH-1:0] channel_col_q[0:MAX_CHANNELS-1];
  logic signed [DATA_WIDTH-1:0] horiz_hold_q[0:MAX_CHANNELS-1];
  logic signed [DATA_WIDTH-1:0] prev_row_hmax_q[0:MAX_CHANNELS-1][0:MAX_POOL_COLS-1];

  function automatic logic signed [DATA_WIDTH-1:0] max_i8(
      input logic signed [DATA_WIDTH-1:0] a_i,
      input logic signed [DATA_WIDTH-1:0] b_i
  );
    begin
      max_i8 = (a_i > b_i) ? a_i : b_i;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ub_wr_en_o   <= 1'b0;
      ub_wr_bank_o <= 1'b0;
      ub_wr_addr_o <= '0;
      ub_wr_data_o <= '0;

      for (int ch = 0; ch < MAX_CHANNELS; ch++) begin
        channel_row_q[ch] <= '0;
        channel_col_q[ch] <= '0;
        horiz_hold_q[ch]  <= '0;
        for (int col = 0; col < MAX_POOL_COLS; col++) begin
          prev_row_hmax_q[ch][col] <= '0;
        end
      end
    end else begin
      ub_wr_en_o <= 1'b0;

      if (clear_i) begin
        ub_wr_bank_o <= 1'b0;
        ub_wr_addr_o <= '0;
        ub_wr_data_o <= '0;

        for (int ch = 0; ch < MAX_CHANNELS; ch++) begin
          channel_row_q[ch] <= '0;
          channel_col_q[ch] <= '0;
          horiz_hold_q[ch]  <= '0;
          for (int col = 0; col < MAX_POOL_COLS; col++) begin
            prev_row_hmax_q[ch][col] <= '0;
          end
        end
      end else if (enable_i && stream_valid_i
                   && (stream_channel_idx_i < DIM_WIDTH'(MAX_CHANNELS))
                   && (stream_channel_idx_i < output_ch_i)
                   && (input_w_i != '0)) begin
        int ch_idx;
        int pool_col_idx;
        logic [DIM_WIDTH-1:0] row_curr;
        logic [DIM_WIDTH-1:0] col_curr;
        logic [DIM_WIDTH-1:0] pool_row;
        logic [DIM_WIDTH-1:0] pool_col;
        logic signed [DATA_WIDTH-1:0] horiz_max_v;
        logic signed [DATA_WIDTH-1:0] pooled_max_v;
        logic [ADDR_CALC_WIDTH-1:0] out_channel_stride_v;
        logic [ADDR_CALC_WIDTH-1:0] write_addr_v;

        ch_idx = int'(stream_channel_idx_i);
        row_curr = channel_row_q[ch_idx];
        col_curr = channel_col_q[ch_idx];
        pool_row = row_curr >> 1;
        pool_col = col_curr >> 1;
        pool_col_idx = int'(pool_col);
        horiz_max_v = max_i8(horiz_hold_q[ch_idx], stream_data_i);

        if (!col_curr[0]) begin
          horiz_hold_q[ch_idx] <= stream_data_i;
        end else if (!row_curr[0]) begin
          if (pool_col_idx < MAX_POOL_COLS) begin
            prev_row_hmax_q[ch_idx][pool_col_idx] <= horiz_max_v;
          end
        end else if ((pool_col_idx < MAX_POOL_COLS)
                     && (pool_row < output_h_i)
                     && (pool_col < output_w_i)) begin
          pooled_max_v = max_i8(prev_row_hmax_q[ch_idx][pool_col_idx], horiz_max_v);
          out_channel_stride_v = ADDR_CALC_WIDTH'(output_h_i) * ADDR_CALC_WIDTH'(output_w_i);
          write_addr_v = ADDR_CALC_WIDTH'(output_base_addr_i)
                       + (ADDR_CALC_WIDTH'(stream_channel_idx_i) * out_channel_stride_v)
                       + (ADDR_CALC_WIDTH'(pool_row) * ADDR_CALC_WIDTH'(output_w_i))
                       + ADDR_CALC_WIDTH'(pool_col);

          ub_wr_en_o   <= 1'b1;
          ub_wr_bank_o <= write_bank_i;
          ub_wr_addr_o <= ADDR_WIDTH'(write_addr_v);
          ub_wr_data_o <= pooled_max_v;
        end

        if ((col_curr + DIM_WIDTH'(1)) >= input_w_i) begin
          channel_col_q[ch_idx] <= '0;
          channel_row_q[ch_idx] <= row_curr + DIM_WIDTH'(1);
        end else begin
          channel_col_q[ch_idx] <= col_curr + DIM_WIDTH'(1);
        end
      end
    end
  end

endmodule : streaming_maxpool_writeback
