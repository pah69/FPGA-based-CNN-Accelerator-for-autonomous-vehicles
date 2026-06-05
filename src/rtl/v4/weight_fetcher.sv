`timescale 1ns / 1ps

module weight_fetcher #(
    parameter int SIZE             = 2,
    parameter int DATA_WIDTH       = 8,
    parameter int FIFO_COUNT_WIDTH = 5,
    parameter int ROW_COUNT_WIDTH  = (SIZE > 1) ? $clog2(SIZE + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input  logic start_load_i,
    output logic ready_o,

    // Synchronous FIFO interface. A pop makes fifo_data_i valid next cycle.
    input  logic [(DATA_WIDTH*SIZE)-1:0] fifo_data_i,
    input  logic                         fifo_empty_i,
    input  logic [ FIFO_COUNT_WIDTH-1:0] fifo_count_i,
    output logic                         fifo_pop_o,

    // Weight stream into the systolic array. FIFO must be filled bottom-row first.
    output logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_o,
    output logic        [             SIZE-1:0] wgt_load_o,
    output logic                                weight_switch_o
);

  typedef enum logic [1:0] {
    IDLE,
    POP_FIRST,
    LOAD_ROWS,
    SWITCH
  } state_t;

  state_t state, next_state;
  logic [ROW_COUNT_WIDTH-1:0] rows_loaded_q;
  logic                       enough_rows;

  assign enough_rows = !fifo_empty_i && (fifo_count_i >= FIFO_COUNT_WIDTH'(SIZE));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= IDLE;
      rows_loaded_q <= '0;
    end else begin
      state <= next_state;

      if (state == IDLE) begin
        rows_loaded_q <= '0;
      end else if (state == LOAD_ROWS) begin
        rows_loaded_q <= rows_loaded_q + ROW_COUNT_WIDTH'(1);
      end
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
        if (start_load_i && enough_rows) begin
          next_state = POP_FIRST;
        end
      end
      POP_FIRST: begin
        next_state = LOAD_ROWS;
      end
      LOAD_ROWS: begin
        if (rows_loaded_q == ROW_COUNT_WIDTH'(SIZE - 1)) begin
          next_state = SWITCH;
        end
      end
      SWITCH: begin
        next_state = IDLE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_comb begin
    ready_o         = 1'b0;
    fifo_pop_o      = 1'b0;
    wgt_flatten_o   = '0;
    wgt_load_o      = '0;
    weight_switch_o = 1'b0;

    case (state)
      IDLE: begin
        ready_o = enough_rows;
      end

      POP_FIRST: begin
        fifo_pop_o = 1'b1;
      end

      LOAD_ROWS: begin
        wgt_flatten_o = fifo_data_i;
        wgt_load_o    = {SIZE{1'b1}};

        if (rows_loaded_q < ROW_COUNT_WIDTH'(SIZE - 1)) begin
          fifo_pop_o = 1'b1;
        end
      end

      SWITCH: begin
        weight_switch_o = 1'b1;
      end

      default: begin
      end
    endcase
  end

endmodule : weight_fetcher
