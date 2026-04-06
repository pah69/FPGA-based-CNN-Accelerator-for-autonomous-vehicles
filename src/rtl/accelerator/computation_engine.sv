

`timescale 1ns / 1ps

module computation_engine #(
    parameter DATA_WIDTH = 17,
    parameter ROWS       = 4,
    parameter COLS       = 4,
    parameter ACC_WIDTH  = (2 * DATA_WIDTH) + 1
) (
    input logic clk,
    input logic rst_n,

    // vectors from buffers
    input logic [ROWS*DATA_WIDTH-1:0] act_vec_i,
    input logic [COLS*DATA_WIDTH-1:0] weight_vec_i,

    // local_activation controls
    input logic act_local_load_i,
    input logic act_fire_i,
    input logic act_start_fire_i,
    input logic act_clear_fire_i,

    // local_weight controls
    input logic weight_local_load_i,
    input logic pe_weight_load_i,

    // local_output capture
    input logic capture_results_i,

    output logic [ROWS*COLS*ACC_WIDTH-1:0] result_vec_o,
    output logic                           result_valid_o,
    output logic                           array_all_valid_o
);

  logic signed [DATA_WIDTH-1:0] act_rows        [0:ROWS-1];
  logic                         act_valid_s;
  logic                         act_start_s;
  logic                         act_clear_s;

  logic signed [DATA_WIDTH-1:0] weight_cols     [0:COLS-1];
  logic                         weight_load_cols[0:COLS-1];

  logic signed [ ACC_WIDTH-1:0] array_result    [0:ROWS-1] [0:COLS-1];
  logic                         array_valid     [0:ROWS-1] [0:COLS-1];
  logic signed [DATA_WIDTH-1:0] weight_dbg      [0:ROWS-1] [0:COLS-1];

  integer r, c;

//   local_activation #(
//       .DATA_WIDTH(DATA_WIDTH),
//       .ROWS      (ROWS)
//   ) u_local_activation (
//       .clk         (clk),
//       .rst         (~rst_n),
//       .local_load_i(act_local_load_i),
//       .act_vec_in  (act_vec_i),
//       .act_fire_i  (act_fire_i),
//       .start_fire_i(act_start_fire_i),
//       .clear_fire_i(act_clear_fire_i),
//       .act_out     (act_rows),
//       .valid_out   (act_valid_s),
//       .start_out   (act_start_s),
//       .clear_out   (act_clear_s)
//   );

  local_weight #(
      .DATA_WIDTH(DATA_WIDTH),
      .COLS      (COLS)
  ) u_local_weight (
      .clk             (clk),
      .rst             (~rst_n),
      .local_load_i    (weight_local_load_i),
      .weight_vec_in   (weight_vec_i),
      .pe_weight_load_i(pe_weight_load_i),
      .weight_out      (weight_cols),
      .weight_load     (weight_load_cols)
  );

  systolic_array_4x4 #(
      .ROWS      (ROWS),
      .COLS      (COLS),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_systolic_array (
      .clk        (clk),
      .rst_n      (rst_n),
      .act_in     (act_rows),
      .valid_in   (act_valid_s),
      .start_in   (act_start_s),
      .clear_in   (act_clear_s),
      .weight_in  (weight_cols),
      .weight_load(weight_load_cols),
      .result_out (array_result),
      .valid_out  (array_valid),
      .weight_dbg (weight_dbg)
  );

//   always_comb begin
//     array_all_valid_o = 1'b1;
//     for (r = 0; r < ROWS; r = r + 1) begin
//       for (c = 0; c < COLS; c = c + 1) begin
//         array_all_valid_o = array_all_valid_o & array_valid[r][c];
//       end
//     end
//   end

  local_output #(
      .DATA_WIDTH(ACC_WIDTH),
      .ROWS      (ROWS),
      .COLS      (COLS)
  ) u_local_output (
      .clk           (clk),
      .rst           (~rst_n),
      .result_valid_i(capture_results_i),
      .result_in     (array_result),
      .result_valid_o(result_valid_o),
      .result_vec_o  (result_vec_o)
  );

endmodule
