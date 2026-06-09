`timescale 1ns / 1ps

module pooling_unit #(
    parameter int SIZE        = 2,
    parameter int DATA_WIDTH  = 8,
    parameter int POOL_MODE   = 0,
    parameter int POOL_WINDOW = 2
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] data_flatten_i,
    input logic                                data_valid_i,
    input logic                                done_i,

    output logic signed [(DATA_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic                                data_valid_o,
    output logic                                done_o
);

  localparam int POOL_BYPASS = 0;
  localparam int POOL_MAX = 1;
  localparam int POOL_AVG = 2;
  localparam int COUNT_WIDTH = (POOL_WINDOW > 1) ? $clog2(POOL_WINDOW + 1) : 1;
  localparam int SUM_WIDTH = DATA_WIDTH + ((POOL_WINDOW > 1) ? $clog2(POOL_WINDOW) : 1);

  logic signed [ DATA_WIDTH-1:0] lane_data_i  [0:SIZE-1];
  logic signed [  SUM_WIDTH-1:0] pool_sum_q   [0:SIZE-1];
  logic signed [ DATA_WIDTH-1:0] pool_max_q   [0:SIZE-1];
  logic        [COUNT_WIDTH-1:0] pool_count_q;

  function automatic logic signed [DATA_WIDTH-1:0] pool_average(
      input logic signed [SUM_WIDTH-1:0] sum_i, input logic [COUNT_WIDTH-1:0] count_i);
    logic signed [ SUM_WIDTH-1:0] count_value;
    logic signed [DATA_WIDTH-1:0] avg_value;
    begin
      count_value  = SUM_WIDTH'(count_i);
      avg_value    = DATA_WIDTH'(sum_i / count_value);
      pool_average = avg_value;
    end
  endfunction

  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      lane_data_i[lane] = data_flatten_i[(lane*DATA_WIDTH)+:DATA_WIDTH];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_flatten_o <= '0;
      data_valid_o   <= 1'b0;
      done_o         <= 1'b0;
      pool_count_q   <= '0;

      for (int lane = 0; lane < SIZE; lane++) begin
        pool_sum_q[lane] <= '0;
        pool_max_q[lane] <= '0;
      end
    end else begin
      data_valid_o <= 1'b0;
      done_o       <= 1'b0;

      if ((POOL_MODE == POOL_BYPASS) || (POOL_WINDOW == 1)) begin
        if (data_valid_i) begin
          for (int lane = 0; lane < SIZE; lane++) begin
            data_flatten_o[(lane*DATA_WIDTH)+:DATA_WIDTH] <= lane_data_i[lane];
          end

          data_valid_o <= 1'b1;
          done_o       <= done_i;
        end
      end else if (data_valid_i) begin
        int unsigned sample_count_next;

        sample_count_next = int'(pool_count_q) + 1;

        for (int lane = 0; lane < SIZE; lane++) begin
          logic signed [ SUM_WIDTH-1:0] sum_next;
          logic signed [DATA_WIDTH-1:0] max_next;

          if (pool_count_q == 0) begin
            sum_next = {
              {(SUM_WIDTH - DATA_WIDTH) {lane_data_i[lane][DATA_WIDTH-1]}}, lane_data_i[lane]
            };
            max_next = lane_data_i[lane];
          end else begin
            sum_next = pool_sum_q[lane] + lane_data_i[lane];

            if (lane_data_i[lane] > pool_max_q[lane]) begin
              max_next = lane_data_i[lane];
            end else begin
              max_next = pool_max_q[lane];
            end
          end

          if ((sample_count_next == POOL_WINDOW) || done_i) begin
            if (POOL_MODE == POOL_MAX) begin
              data_flatten_o[(lane*DATA_WIDTH)+:DATA_WIDTH] <= max_next;
            end else if (POOL_MODE == POOL_AVG) begin
              data_flatten_o[(lane*DATA_WIDTH)+:DATA_WIDTH] <=
                  pool_average(sum_next, COUNT_WIDTH'(sample_count_next));
            end else begin
              data_flatten_o[(lane*DATA_WIDTH)+:DATA_WIDTH] <= lane_data_i[lane];
            end

            pool_sum_q[lane] <= '0;
            pool_max_q[lane] <= '0;
          end else begin
            pool_sum_q[lane] <= sum_next;
            pool_max_q[lane] <= max_next;
          end
        end

        if ((sample_count_next == POOL_WINDOW) || done_i) begin
          pool_count_q <= '0;
          data_valid_o <= 1'b1;
          done_o       <= done_i;
        end else begin
          pool_count_q <= pool_count_q + 1'b1;
        end
      end
    end
  end

endmodule : pooling_unit_v2
