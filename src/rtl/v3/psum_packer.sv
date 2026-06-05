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
    input logic capture_en_i,
    input logic [ADDR_WIDTH-1:0] write_addr_i,

    input logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input logic        [                   SIZE-1:0] psum_valid_i,

    output logic                                      packed_valid_o,
    output logic        [             ADDR_WIDTH-1:0] packed_write_addr_o,
    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] packed_psum_flatten_o,
    output logic        [                   SIZE-1:0] packed_psum_valid_o,
    output logic                                      busy_o
);

  localparam int ENTRY_COUNT = (1 << ADDR_WIDTH);
  localparam int COUNT_WIDTH = ADDR_WIDTH + 1;

  logic row_active_q[0:ENTRY_COUNT-1];
  logic [SIZE-1:0] row_lane_valid_q[0:ENTRY_COUNT-1];
  logic signed [LOCAL_PSUM_WIDTH-1:0] row_lane_data_q[0:ENTRY_COUNT-1][0:SIZE-1];

  logic [ADDR_WIDTH-1:0] lane_addr_fifo_q[0:SIZE-1][0:ENTRY_COUNT-1];
  logic [ADDR_WIDTH-1:0] lane_head_q[0:SIZE-1];
  logic [ADDR_WIDTH-1:0] lane_tail_q[0:SIZE-1];
  logic [COUNT_WIDTH-1:0] lane_count_q[0:SIZE-1];

  logic complete_any_w;
  logic [ADDR_WIDTH-1:0] complete_addr_w;

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
    complete_addr_w = '0;

    for (int row = 0; row < ENTRY_COUNT; row++) begin
      if (!complete_any_w && row_active_q[row] && (&row_lane_valid_q[row])) begin
        complete_any_w  = 1'b1;
        complete_addr_w = ADDR_WIDTH'(row);
      end
    end
  end

  always_comb begin
    busy_o = 1'b0;

    for (int row = 0; row < ENTRY_COUNT; row++) begin
      busy_o |= row_active_q[row];
    end

    for (int lane = 0; lane < SIZE; lane++) begin
      busy_o |= (lane_count_q[lane] != '0);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      packed_valid_o        <= 1'b0;
      packed_write_addr_o   <= '0;
      packed_psum_flatten_o <= '0;
      packed_psum_valid_o   <= '0;

      for (int row = 0; row < ENTRY_COUNT; row++) begin
        row_active_q[row] <= 1'b0;
        row_lane_valid_q[row] <= '0;

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
    end else if (clear_i) begin
      packed_valid_o        <= 1'b0;
      packed_write_addr_o   <= '0;
      packed_psum_flatten_o <= '0;
      packed_psum_valid_o   <= '0;

      for (int row = 0; row < ENTRY_COUNT; row++) begin
        row_active_q[row] <= 1'b0;
        row_lane_valid_q[row] <= '0;

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
      end

      if (capture_en_i) begin
        row_active_q[write_addr_i] <= 1'b1;
        row_lane_valid_q[write_addr_i] <= '0;

        for (int lane = 0; lane < SIZE; lane++) begin
          row_lane_data_q[write_addr_i][lane] <= '0;
        end
      end

      for (int lane = 0; lane < SIZE; lane++) begin
        logic push_w;
        logic pop_w;
        logic [ADDR_WIDTH-1:0] pop_addr_w;

        push_w = capture_en_i && (lane_count_q[lane] != COUNT_WIDTH'(ENTRY_COUNT));
        pop_w = psum_valid_i[lane] && (lane_count_q[lane] != '0);
        pop_addr_w = lane_addr_fifo_q[lane][lane_head_q[lane]];

        if (push_w) begin
          lane_addr_fifo_q[lane][lane_tail_q[lane]] <= write_addr_i;
          lane_tail_q[lane] <= next_ptr(lane_tail_q[lane]);
        end

        if (pop_w) begin
          row_lane_data_q[pop_addr_w][lane] <=
              psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
          row_lane_valid_q[pop_addr_w][lane] <= 1'b1;
          lane_head_q[lane] <= next_ptr(lane_head_q[lane]);
        end

        unique case ({push_w, pop_w})
          2'b10: lane_count_q[lane] <= lane_count_q[lane] + COUNT_WIDTH'(1);
          2'b01: lane_count_q[lane] <= lane_count_q[lane] - COUNT_WIDTH'(1);
          default: begin
          end
        endcase
      end
    end
  end

endmodule : psum_packer
