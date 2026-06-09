`timescale 1ns / 1ps

// V3 psum collector.
//
// The historical V2 packer could only hold one partially collected output row.
// A 4x4 array can have psum lanes from several launched rows in flight at the
// same time, so this collector tracks pending row addresses per output lane and
// assembles completed accumulator rows with a small scoreboard.
module psum_packer #(
    parameter int SIZE             = 2,
    parameter int LOCAL_PSUM_WIDTH = 18,
    parameter int ADDR_WIDTH       = 4
) (
    input logic clk,
    input logic rst_n,

    // In V3 this is a row-launch event, not a raw psum capture gate.
    input logic clear_i,
    input logic dbg_counter_clear_i,
    input logic capture_en_i,
    input logic [ADDR_WIDTH-1:0] write_addr_i,

    input logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input logic        [                   SIZE-1:0] psum_valid_i,

    output logic                                      packed_valid_o,
    output logic        [             ADDR_WIDTH-1:0] packed_write_addr_o,
    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] packed_psum_flatten_o,
    output logic        [                   SIZE-1:0] packed_psum_valid_o,
    output logic                                      busy_o,

    output logic [31:0] dbg_lane_fifo_nonempty_cycles_o,
    output logic [31:0] dbg_row_active_cycles_o,
    output logic [31:0] dbg_complete_row_wait_cycles_o,
    output logic [31:0] dbg_packed_valid_cycles_o,
    output logic [31:0] dbg_packer_busy_cycles_o,
    output logic [31:0] dbg_lane_fifo_full_cycles_o,
    output logic [31:0] dbg_lane_fifo_empty_cycles_o,
    output logic [31:0] dbg_complete_row_backlog_cycles_o,
    output logic [(32*SIZE)-1:0] dbg_lane_psum_valid_cycles_flat_o,
    output logic [(32*SIZE)-1:0] dbg_lane_pop_cycles_flat_o,
    output logic [(32*SIZE)-1:0] dbg_lane_last_arrival_count_flat_o,
    output logic [31:0] dbg_row_completion_latency_sum_o,
    output logic [31:0] dbg_row_completion_latency_max_o
);

  localparam int ENTRY_COUNT = (1 << ADDR_WIDTH);
  localparam int COUNT_WIDTH = ADDR_WIDTH + 1;

  logic row_active_q[0:ENTRY_COUNT-1];
  logic [SIZE-1:0] row_lane_valid_q[0:ENTRY_COUNT-1];
  logic signed [LOCAL_PSUM_WIDTH-1:0] row_lane_data_q[0:ENTRY_COUNT-1][0:SIZE-1];
  logic [31:0] row_partial_age_q[0:ENTRY_COUNT-1];

  logic [ADDR_WIDTH-1:0] lane_addr_fifo_q[0:SIZE-1][0:ENTRY_COUNT-1];
  logic [ADDR_WIDTH-1:0] lane_head_q[0:SIZE-1];
  logic [ADDR_WIDTH-1:0] lane_tail_q[0:SIZE-1];
  logic [COUNT_WIDTH-1:0] lane_count_q[0:SIZE-1];

  logic complete_any_w;
  logic multiple_complete_w;
  logic [ADDR_WIDTH-1:0] complete_addr_w;
  logic lane_fifo_nonempty_w;
  logic lane_fifo_full_w;
  logic row_active_w;
  logic partial_row_wait_w;
  logic missing_lane_empty_w;
  logic lane_pop_w[0:SIZE-1];
  logic [ADDR_WIDTH-1:0] lane_pop_addr_w[0:SIZE-1];
  logic [SIZE-1:0] row_lane_valid_after_pop_w[0:ENTRY_COUNT-1];
  logic row_complete_this_cycle_w[0:ENTRY_COUNT-1];
  logic [SIZE-1:0] row_last_lane_mask_w[0:ENTRY_COUNT-1];
  logic [(32*SIZE)-1:0] lane_last_arrival_inc_flat_w;
  logic [31:0] row_completion_latency_add_w;
  logic [31:0] row_completion_latency_max_w;

  function automatic logic [ADDR_WIDTH-1:0] next_ptr(
      input logic [ADDR_WIDTH-1:0] ptr_i);
    begin
      if (ptr_i == ADDR_WIDTH'(ENTRY_COUNT - 1)) begin
        next_ptr = '0;
      end else begin
        next_ptr = ptr_i + ADDR_WIDTH'(1);
      end
    end
  endfunction

  always_comb begin
    complete_any_w  = 1'b0;
    multiple_complete_w = 1'b0;
    complete_addr_w = '0;

    for (int row = 0; row < ENTRY_COUNT; row++) begin
      if (row_active_q[row] && (&row_lane_valid_q[row])) begin
        if (!complete_any_w) begin
          complete_any_w  = 1'b1;
          complete_addr_w = ADDR_WIDTH'(row);
        end else begin
          multiple_complete_w = 1'b1;
        end
      end
    end
  end

  always_comb begin
    lane_fifo_nonempty_w = 1'b0;
    lane_fifo_full_w = 1'b0;
    row_active_w = 1'b0;
    partial_row_wait_w = 1'b0;
    missing_lane_empty_w = 1'b0;
    lane_last_arrival_inc_flat_w = '0;
    row_completion_latency_add_w = '0;
    row_completion_latency_max_w = '0;

    for (int row = 0; row < ENTRY_COUNT; row++) begin
      row_lane_valid_after_pop_w[row] = row_lane_valid_q[row];
    end

    for (int lane = 0; lane < SIZE; lane++) begin
      lane_pop_w[lane] = psum_valid_i[lane] && (lane_count_q[lane] != '0);
      lane_pop_addr_w[lane] = lane_addr_fifo_q[lane][lane_head_q[lane]];

      if (lane_pop_w[lane]) begin
        row_lane_valid_after_pop_w[lane_pop_addr_w[lane]][lane] = 1'b1;
      end
    end

    for (int row = 0; row < ENTRY_COUNT; row++) begin
      row_active_w |= row_active_q[row];
      row_complete_this_cycle_w[row] =
          row_active_q[row] && !(&row_lane_valid_q[row]) && (&row_lane_valid_after_pop_w[row]);
      row_last_lane_mask_w[row] = row_lane_valid_after_pop_w[row] & ~row_lane_valid_q[row];

      if (row_complete_this_cycle_w[row]) begin
        row_completion_latency_add_w += row_partial_age_q[row];
        if (row_partial_age_q[row] > row_completion_latency_max_w) begin
          row_completion_latency_max_w = row_partial_age_q[row];
        end

        for (int lane = 0; lane < SIZE; lane++) begin
          if (row_last_lane_mask_w[row][lane]) begin
            lane_last_arrival_inc_flat_w[(lane*32)+:32] += 32'd1;
          end
        end
      end

      if (row_active_q[row] && (row_lane_valid_q[row] != '0) && !(&row_lane_valid_q[row])) begin
        partial_row_wait_w = 1'b1;

        for (int lane = 0; lane < SIZE; lane++) begin
          if (!row_lane_valid_q[row][lane] && (lane_count_q[lane] == '0)) begin
            missing_lane_empty_w = 1'b1;
          end
        end
      end
    end

    for (int lane = 0; lane < SIZE; lane++) begin
      lane_fifo_nonempty_w |= (lane_count_q[lane] != '0);
      lane_fifo_full_w |= (lane_count_q[lane] == COUNT_WIDTH'(ENTRY_COUNT));
    end

    busy_o = row_active_w || lane_fifo_nonempty_w;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      packed_valid_o        <= 1'b0;
      packed_write_addr_o   <= '0;
      packed_psum_flatten_o <= '0;
      packed_psum_valid_o   <= '0;
      dbg_lane_fifo_nonempty_cycles_o <= '0;
      dbg_row_active_cycles_o <= '0;
      dbg_complete_row_wait_cycles_o <= '0;
      dbg_packed_valid_cycles_o <= '0;
      dbg_packer_busy_cycles_o <= '0;
      dbg_lane_fifo_full_cycles_o <= '0;
      dbg_lane_fifo_empty_cycles_o <= '0;
      dbg_complete_row_backlog_cycles_o <= '0;
      dbg_lane_psum_valid_cycles_flat_o <= '0;
      dbg_lane_pop_cycles_flat_o <= '0;
      dbg_lane_last_arrival_count_flat_o <= '0;
      dbg_row_completion_latency_sum_o <= '0;
      dbg_row_completion_latency_max_o <= '0;

      for (int row = 0; row < ENTRY_COUNT; row++) begin
        row_active_q[row] <= 1'b0;
        row_lane_valid_q[row] <= '0;
        row_partial_age_q[row] <= '0;

        for (int lane = 0; lane < SIZE; lane++) begin
          row_lane_data_q[row][lane] <= '0;
        end
      end

      for (int lane = 0; lane < SIZE; lane++) begin
        lane_head_q[lane] <= '0;
        lane_tail_q[lane] <= '0;
        lane_count_q[lane] <= '0;

        for (int entry = 0; entry < ENTRY_COUNT; entry++) begin
          lane_addr_fifo_q[lane][entry] <= '0;
        end
      end
    end else begin
      if (dbg_counter_clear_i) begin
        dbg_lane_fifo_nonempty_cycles_o <= '0;
        dbg_row_active_cycles_o <= '0;
        dbg_complete_row_wait_cycles_o <= '0;
        dbg_packed_valid_cycles_o <= '0;
        dbg_packer_busy_cycles_o <= '0;
        dbg_lane_fifo_full_cycles_o <= '0;
        dbg_lane_fifo_empty_cycles_o <= '0;
        dbg_complete_row_backlog_cycles_o <= '0;
        dbg_lane_psum_valid_cycles_flat_o <= '0;
        dbg_lane_pop_cycles_flat_o <= '0;
        dbg_lane_last_arrival_count_flat_o <= '0;
        dbg_row_completion_latency_sum_o <= '0;
        dbg_row_completion_latency_max_o <= '0;
        for (int row = 0; row < ENTRY_COUNT; row++) begin
          row_partial_age_q[row] <= '0;
        end
      end else begin
        if (lane_fifo_nonempty_w) begin
          dbg_lane_fifo_nonempty_cycles_o <= dbg_lane_fifo_nonempty_cycles_o + 32'd1;
        end
        if (row_active_w) begin
          dbg_row_active_cycles_o <= dbg_row_active_cycles_o + 32'd1;
        end
        if (partial_row_wait_w) begin
          dbg_complete_row_wait_cycles_o <= dbg_complete_row_wait_cycles_o + 32'd1;
        end
        if (complete_any_w) begin
          dbg_packed_valid_cycles_o <= dbg_packed_valid_cycles_o + 32'd1;
        end
        if (busy_o) begin
          dbg_packer_busy_cycles_o <= dbg_packer_busy_cycles_o + 32'd1;
        end
        if (lane_fifo_full_w) begin
          dbg_lane_fifo_full_cycles_o <= dbg_lane_fifo_full_cycles_o + 32'd1;
        end
        if (missing_lane_empty_w) begin
          dbg_lane_fifo_empty_cycles_o <= dbg_lane_fifo_empty_cycles_o + 32'd1;
        end
        if (multiple_complete_w) begin
          dbg_complete_row_backlog_cycles_o <= dbg_complete_row_backlog_cycles_o + 32'd1;
        end

        for (int lane = 0; lane < SIZE; lane++) begin
          if (psum_valid_i[lane]) begin
            dbg_lane_psum_valid_cycles_flat_o[(lane*32)+:32] <=
                dbg_lane_psum_valid_cycles_flat_o[(lane*32)+:32] + 32'd1;
          end
          if (lane_pop_w[lane]) begin
            dbg_lane_pop_cycles_flat_o[(lane*32)+:32] <=
                dbg_lane_pop_cycles_flat_o[(lane*32)+:32] + 32'd1;
          end
        end

        if (row_completion_latency_add_w != '0) begin
          dbg_row_completion_latency_sum_o <=
              dbg_row_completion_latency_sum_o + row_completion_latency_add_w;
        end
        if (row_completion_latency_max_w > dbg_row_completion_latency_max_o) begin
          dbg_row_completion_latency_max_o <= row_completion_latency_max_w;
        end
        for (int lane = 0; lane < SIZE; lane++) begin
          if (lane_last_arrival_inc_flat_w[(lane*32)+:32] != '0) begin
            dbg_lane_last_arrival_count_flat_o[(lane*32)+:32] <=
                dbg_lane_last_arrival_count_flat_o[(lane*32)+:32]
                + lane_last_arrival_inc_flat_w[(lane*32)+:32];
          end
        end
      end

      if (clear_i) begin
        packed_valid_o        <= 1'b0;
        packed_write_addr_o   <= '0;
        packed_psum_flatten_o <= '0;
        packed_psum_valid_o   <= '0;

        for (int row = 0; row < ENTRY_COUNT; row++) begin
          row_active_q[row] <= 1'b0;
          row_lane_valid_q[row] <= '0;
          row_partial_age_q[row] <= '0;

          for (int lane = 0; lane < SIZE; lane++) begin
            row_lane_data_q[row][lane] <= '0;
          end
        end

        for (int lane = 0; lane < SIZE; lane++) begin
          lane_head_q[lane] <= '0;
          lane_tail_q[lane] <= '0;
          lane_count_q[lane] <= '0;
        end
      end else begin
        packed_valid_o      <= 1'b0;
        packed_psum_valid_o <= '0;

        for (int row = 0; row < ENTRY_COUNT; row++) begin
          if (row_active_q[row] && (row_lane_valid_q[row] != '0)
              && !(&row_lane_valid_q[row]) && !row_complete_this_cycle_w[row]) begin
            row_partial_age_q[row] <= row_partial_age_q[row] + 32'd1;
          end
        end

        if (complete_any_w) begin
          packed_valid_o      <= 1'b1;
          packed_write_addr_o <= complete_addr_w;
          packed_psum_valid_o <= {SIZE{1'b1}};

          for (int lane = 0; lane < SIZE; lane++) begin
            packed_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] <=
                row_lane_data_q[complete_addr_w][lane];
          end

          row_active_q[complete_addr_w] <= 1'b0;
          row_lane_valid_q[complete_addr_w] <= '0;
          row_partial_age_q[complete_addr_w] <= '0;
        end

        if (capture_en_i) begin
          row_active_q[write_addr_i] <= 1'b1;
          row_lane_valid_q[write_addr_i] <= '0;
          row_partial_age_q[write_addr_i] <= '0;

          for (int lane = 0; lane < SIZE; lane++) begin
            row_lane_data_q[write_addr_i][lane] <= '0;
          end
        end

        for (int lane = 0; lane < SIZE; lane++) begin
          logic push_w;
          logic [ADDR_WIDTH-1:0] pop_addr_w;

          push_w = capture_en_i && (lane_count_q[lane] != COUNT_WIDTH'(ENTRY_COUNT));
          pop_addr_w = lane_pop_addr_w[lane];

          if (push_w) begin
            lane_addr_fifo_q[lane][lane_tail_q[lane]] <= write_addr_i;
            lane_tail_q[lane] <= next_ptr(lane_tail_q[lane]);
          end

          if (lane_pop_w[lane]) begin
            row_lane_data_q[pop_addr_w][lane] <=
                psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
            row_lane_valid_q[pop_addr_w][lane] <= 1'b1;
            lane_head_q[lane] <= next_ptr(lane_head_q[lane]);
          end

          unique case ({push_w, lane_pop_w[lane]})
            2'b10: lane_count_q[lane] <= lane_count_q[lane] + COUNT_WIDTH'(1);
            2'b01: lane_count_q[lane] <= lane_count_q[lane] - COUNT_WIDTH'(1);
            default: begin
            end
          endcase
        end
      end
    end
  end

endmodule : psum_packer
