`timescale 1ns / 1ps

module activation_array_v2 #(
    parameter int SIZE            = 2,
    parameter int IN_WIDTH        = 18,
    parameter int OUT_WIDTH       = IN_WIDTH,
    parameter int ACT_MODE        = 1,
    parameter int CLIP_MAX        = 6,
    parameter int ACT_INPUT_SHIFT = 0,
    parameter int ACT_FRAC_BITS   = 8
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(IN_WIDTH*SIZE)-1:0] data_flatten_i,
    input logic                              data_valid_i,
    input logic                              done_i,
    input logic [1:0]                        act_mode_i,

    output logic signed [(OUT_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic                               data_valid_o,
    output logic                               done_o
);

  localparam logic [1:0] ACT_BYPASS = 2'd0;
  localparam logic [1:0] ACT_RELU = 2'd1;

  logic signed [ IN_WIDTH-1:0] lane_data_i  [0:SIZE-1];
  logic signed [OUT_WIDTH-1:0] lane_data_act[0:SIZE-1];

  function automatic logic signed [OUT_WIDTH-1:0] sat_resize(
      input logic signed [IN_WIDTH-1:0] value_i);
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

  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      lane_data_i[lane] = data_flatten_i[(lane*IN_WIDTH)+:IN_WIDTH];

      case (act_mode_i)
        ACT_BYPASS: lane_data_act[lane] = sat_resize(lane_data_i[lane]);
        ACT_RELU: begin
          if (lane_data_i[lane] < 0) begin
            lane_data_act[lane] = '0;
          end else begin
            lane_data_act[lane] = sat_resize(lane_data_i[lane]);
          end
        end
        default: lane_data_act[lane] = sat_resize(lane_data_i[lane]);
      endcase
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
          data_flatten_o[(lane*OUT_WIDTH)+:OUT_WIDTH] <= lane_data_act[lane];
        end
      end

      data_valid_o <= data_valid_i;
      done_o       <= data_valid_i && done_i;
    end
  end

endmodule : activation_array_v2
