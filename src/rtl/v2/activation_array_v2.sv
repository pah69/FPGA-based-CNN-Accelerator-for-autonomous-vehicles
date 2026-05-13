`timescale 1ns / 1ps

module activation_array_v2 #(
    parameter int SIZE      = 2,
    parameter int IN_WIDTH  = 18,
    parameter int OUT_WIDTH = IN_WIDTH,
    parameter int ACT_MODE  = 1,
    parameter int CLIP_MAX  = 6,
    parameter int ACT_INPUT_SHIFT = 0,
    parameter int ACT_FRAC_BITS   = 8
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

  localparam int ACT_BYPASS = 0;
  localparam int ACT_RELU   = 1;
  localparam int ACT_RELU6  = 2;
  localparam int ACT_SIGMOID = 3;
  localparam int ACT_TANH    = 4;
  localparam logic signed [IN_WIDTH-1:0] CLIP_MAX_VALUE = IN_WIDTH'($signed(CLIP_MAX));
  localparam int FP_ONE_INT          = 1 << ACT_FRAC_BITS;
  localparam int FP_ONE_HALF_INT     = FP_ONE_INT / 2;
  localparam int FP_ONE_QUARTER_INT  = FP_ONE_INT / 4;
  localparam int FP_ONE_EIGHTH_INT   = FP_ONE_INT / 8;
  localparam int FP_THREE_QUARTER_INT = (3 * FP_ONE_INT) / 4;
  localparam int FP_THREE_EIGHTH_INT  = (3 * FP_ONE_INT) / 8;
  localparam int FP_FIVE_EIGHTH_INT   = (5 * FP_ONE_INT) / 8;
  localparam int FP_SEVEN_EIGHTH_INT  = (7 * FP_ONE_INT) / 8;

  localparam logic signed [IN_WIDTH-1:0] ACT_NEG_FOUR = IN_WIDTH'($signed(-4));
  localparam logic signed [IN_WIDTH-1:0] ACT_NEG_TWO  = IN_WIDTH'($signed(-2));
  localparam logic signed [IN_WIDTH-1:0] ACT_NEG_ONE  = IN_WIDTH'($signed(-1));
  localparam logic signed [IN_WIDTH-1:0] ACT_ZERO     = '0;
  localparam logic signed [IN_WIDTH-1:0] ACT_ONE      = IN_WIDTH'($signed(1));
  localparam logic signed [IN_WIDTH-1:0] ACT_TWO      = IN_WIDTH'($signed(2));
  localparam logic signed [IN_WIDTH-1:0] ACT_FOUR     = IN_WIDTH'($signed(4));

  logic signed [ IN_WIDTH-1:0] lane_data_i  [0:SIZE-1];
  logic signed [OUT_WIDTH-1:0] lane_data_act[0:SIZE-1];

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

  function automatic logic signed [IN_WIDTH-1:0] sigmoid_pwl(
      input logic signed [IN_WIDTH-1:0] value_i
  );
    logic signed [IN_WIDTH-1:0] value_scaled;
    begin
      value_scaled = (ACT_INPUT_SHIFT == 0) ? value_i : (value_i >>> ACT_INPUT_SHIFT);

      if (value_scaled <= ACT_NEG_FOUR) begin
        sigmoid_pwl = '0;
      end else if (value_scaled <= ACT_NEG_TWO) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_ONE_EIGHTH_INT));
      end else if (value_scaled <= ACT_NEG_ONE) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_ONE_QUARTER_INT));
      end else if (value_scaled < ACT_ZERO) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_THREE_EIGHTH_INT));
      end else if (value_scaled == ACT_ZERO) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_ONE_HALF_INT));
      end else if (value_scaled < ACT_ONE) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_FIVE_EIGHTH_INT));
      end else if (value_scaled < ACT_TWO) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_THREE_QUARTER_INT));
      end else if (value_scaled < ACT_FOUR) begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_SEVEN_EIGHTH_INT));
      end else begin
        sigmoid_pwl = IN_WIDTH'($signed(FP_ONE_INT));
      end
    end
  endfunction

  function automatic logic signed [IN_WIDTH-1:0] tanh_pwl(
      input logic signed [IN_WIDTH-1:0] value_i
  );
    logic signed [IN_WIDTH-1:0] value_scaled;
    begin
      value_scaled = (ACT_INPUT_SHIFT == 0) ? value_i : (value_i >>> ACT_INPUT_SHIFT);

      if (value_scaled <= ACT_NEG_FOUR) begin
        tanh_pwl = IN_WIDTH'($signed(-FP_ONE_INT));
      end else if (value_scaled <= ACT_NEG_TWO) begin
        tanh_pwl = IN_WIDTH'($signed(-FP_THREE_QUARTER_INT));
      end else if (value_scaled <= ACT_NEG_ONE) begin
        tanh_pwl = IN_WIDTH'($signed(-FP_ONE_HALF_INT));
      end else if (value_scaled < ACT_ZERO) begin
        tanh_pwl = IN_WIDTH'($signed(-FP_ONE_QUARTER_INT));
      end else if (value_scaled == ACT_ZERO) begin
        tanh_pwl = '0;
      end else if (value_scaled < ACT_ONE) begin
        tanh_pwl = IN_WIDTH'($signed(FP_ONE_QUARTER_INT));
      end else if (value_scaled < ACT_TWO) begin
        tanh_pwl = IN_WIDTH'($signed(FP_ONE_HALF_INT));
      end else if (value_scaled < ACT_FOUR) begin
        tanh_pwl = IN_WIDTH'($signed(FP_THREE_QUARTER_INT));
      end else begin
        tanh_pwl = IN_WIDTH'($signed(FP_ONE_INT));
      end
    end
  endfunction

  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      lane_data_i[lane] = data_flatten_i[(lane*IN_WIDTH)+:IN_WIDTH];

      case (ACT_MODE)
        ACT_BYPASS: lane_data_act[lane] = sat_resize(lane_data_i[lane]);
        ACT_RELU: begin
          if (lane_data_i[lane] < 0) begin
            lane_data_act[lane] = '0;
          end else begin
            lane_data_act[lane] = sat_resize(lane_data_i[lane]);
          end
        end
        ACT_RELU6: begin
          if (lane_data_i[lane] < 0) begin
            lane_data_act[lane] = '0;
          end else if (lane_data_i[lane] > CLIP_MAX_VALUE) begin
            lane_data_act[lane] = sat_resize(CLIP_MAX_VALUE);
          end else begin
            lane_data_act[lane] = sat_resize(lane_data_i[lane]);
          end
        end
        ACT_SIGMOID: lane_data_act[lane] = sat_resize(sigmoid_pwl(lane_data_i[lane]));
        ACT_TANH: lane_data_act[lane] = sat_resize(tanh_pwl(lane_data_i[lane]));
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
