`timescale 1ns / 1ps

module mxu_3x3 #(
    parameter int DATA_WIDTH = 17,
    parameter int PSUM_WIDTH = (2 * DATA_WIDTH) + 8,
    parameter int ACC_WIDTH  = PSUM_WIDTH + 8,
    parameter int SIZE       = 3,
    parameter int INPUT_LEN  = 784,
    parameter int NUM_TILES  = (INPUT_LEN + SIZE - 1) / SIZE
) (
  // general
    input logic clk,
    input logic rst_n,

  // control
    input logic work_i,

  // weight
    input logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i,
    input logic                                wgt_load_i,


  // activation
    input logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_i,
    input logic                                act_valid_i,

  // output
    output logic signed [(ACC_WIDTH*SIZE)-1:0] result_flatten_o,
    output logic                               busy_o,
    output logic                               done_o
);

  logic                                work_d;
  logic                                clear_acc;

  logic signed [(PSUM_WIDTH*SIZE)-1:0] psum_flatten;
  logic        [             SIZE-1:0] psum_valid;

  logic        [             SIZE-1:0] act_valid_vec;

  assign clear_acc = work_i && !work_d;

  // Existing PE array expects per-row valid.
  // For one active input tile, all lanes should stay valid.
  assign act_valid_vec = {SIZE{act_valid_i && busy_o}};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      work_d <= 1'b0;
    end else begin
      work_d <= work_i;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_o <= 1'b0;
    end else if (clear_acc) begin
      busy_o <= 1'b1;
    end else if (done_o) begin
      busy_o <= 1'b0;
    end
  end

  bp_sa_3x3 #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH),
      .SIZE      (SIZE)
  ) u_sa (
      .clk  (clk),
      .rst_n(rst_n),

      .wgt_flatten_i(wgt_flatten_i),
      .wgt_load_i   (wgt_load_i),

      .act_flatten_i(act_flatten_i),
      .act_valid_i  (act_valid_vec),

      .psum_flatten_o(psum_flatten),
      .psum_valid_o  (psum_valid)
  );

  bp_output_accumulator #(
      .SIZE      (SIZE),
      .PSUM_WIDTH(PSUM_WIDTH),
      .ACC_WIDTH (ACC_WIDTH),
      .NUM_TILES (NUM_TILES)
  ) u_out_acc (
      .clk  (clk),
      .rst_n(rst_n),

      .clear_i(clear_acc),

      .psum_flatten_i(psum_flatten),
      .psum_valid_i  (psum_valid),

      .result_flatten_o(result_flatten_o),
      .done_o          (done_o)
  );

endmodule
