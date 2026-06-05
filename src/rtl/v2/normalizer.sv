`timescale 1ns / 1ps

module normalizer #(
    parameter int SIZE       = 2,
    parameter int IN_WIDTH   = 18,
    parameter int OUT_WIDTH  = 8,
    parameter int NORM_SHIFT = 0,
    parameter bit ROUND_ENABLE = 1'b1
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(IN_WIDTH*SIZE)-1:0] data_flatten_i,
    input logic                              data_valid_i,
    input logic                              done_i,

    output logic signed [(OUT_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic                               data_valid_o,
    output logic                               done_o
);

  logic signed [ IN_WIDTH-1:0] lane_data_i   [0:SIZE-1];
  logic signed [OUT_WIDTH-1:0] lane_data_norm[0:SIZE-1];

  function automatic logic signed [OUT_WIDTH-1:0] sat_resize(
      input logic signed [IN_WIDTH-1:0] value_i
  );
    longint signed value_long;
    longint signed max_long;
    longint signed min_long;
    longint signed one_long;
    begin
      if (OUT_WIDTH == IN_WIDTH) begin
        sat_resize = value_i[OUT_WIDTH-1:0];
      end else if (OUT_WIDTH > IN_WIDTH) begin
        sat_resize = {{(OUT_WIDTH - IN_WIDTH) {value_i[IN_WIDTH-1]}}, value_i};
      end else begin
        value_long = {{(64 - IN_WIDTH) {value_i[IN_WIDTH-1]}}, value_i};
        one_long   = 1;
        max_long   = (one_long <<< (OUT_WIDTH - 1)) - 1;
        min_long   = -(one_long <<< (OUT_WIDTH - 1));

        if (value_long > max_long) begin
          sat_resize = {1'b0, {(OUT_WIDTH - 1) {1'b1}}};
        end else if (value_long < min_long) begin
          sat_resize = {1'b1, {(OUT_WIDTH - 1) {1'b0}}};
        end else begin
          sat_resize = value_i[OUT_WIDTH-1:0];
        end
      end
    end
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] normalize_lane(
      input logic signed [IN_WIDTH-1:0] value_i
  );
    logic signed [IN_WIDTH-1:0] rounded_value;
    logic signed [IN_WIDTH-1:0] shifted_value;
    begin
      if (NORM_SHIFT == 0) begin
        shifted_value = value_i;
      end else begin
        rounded_value = value_i;

        if (ROUND_ENABLE) begin
          if (value_i >= 0) begin
            rounded_value = value_i + (IN_WIDTH'($signed(1)) <<< (NORM_SHIFT - 1));
          end else begin
            rounded_value = value_i - (IN_WIDTH'($signed(1)) <<< (NORM_SHIFT - 1));
          end
        end

        shifted_value = rounded_value >>> NORM_SHIFT;
      end

      normalize_lane = sat_resize(shifted_value);
    end
  endfunction

  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      lane_data_i[lane]    = data_flatten_i[(lane*IN_WIDTH)+:IN_WIDTH];
      lane_data_norm[lane] = normalize_lane(lane_data_i[lane]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_flatten_o <= '0;
      data_valid_o   <= 1'b0;
      done_o         <= 1'b0;
    end else begin
      if (data_valid_i) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          data_flatten_o[(lane*OUT_WIDTH)+:OUT_WIDTH] <= lane_data_norm[lane];
        end
      end

      data_valid_o <= data_valid_i;
      done_o       <= data_valid_i && done_i;
    end
  end

endmodule : normalizer_v2
