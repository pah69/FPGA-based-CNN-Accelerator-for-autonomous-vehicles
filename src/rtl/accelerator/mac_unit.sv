`timescale 1ns / 1ps

module mac_unit #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    // Data inputs
    input logic signed [DATA_WIDTH-1:0] mac_a_i,
    input logic signed [DATA_WIDTH-1:0] mac_b_i,

    // Control inputs
    input logic mac_valid_i,
    input logic mac_start,
    input logic mac_acc_clear,

    // Outputs
    output logic                         mac_valid_o,
    output logic signed [DATA_WIDTH*2:0] result
);

  localparam int CTRL_PIPE_DEPTH = 4;

  // output reg
  logic signed [(DATA_WIDTH*2)-1:0] product_o;

  // Control signal pipeline registers (4 stages to match multiplier + accumulator sampling)
  logic [CTRL_PIPE_DEPTH-1:0] valid_pipe;
  logic [CTRL_PIPE_DEPTH-1:0] start_pipe;
  logic [CTRL_PIPE_DEPTH-1:0] clear_pipe;

  // Synchronization 
  // Delay the control signals so the accumulator samples them with the matching product
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_pipe <= '0;
      start_pipe <= '0;
      clear_pipe <= '0;
    end else begin
      valid_pipe[0] <= mac_valid_i;
      valid_pipe[1] <= valid_pipe[0];
      valid_pipe[2] <= valid_pipe[1];
      valid_pipe[3] <= valid_pipe[2];

      start_pipe[0] <= mac_start;
      start_pipe[1] <= start_pipe[0];
      start_pipe[2] <= start_pipe[1];
      start_pipe[3] <= start_pipe[2];

      clear_pipe[0] <= mac_acc_clear;
      clear_pipe[1] <= clear_pipe[0];
      clear_pipe[2] <= clear_pipe[1];
      clear_pipe[3] <= clear_pipe[2];
    end
  end

  // Registers
  logic acc_valid_in;
  logic acc_start;
  logic acc_clear;

  assign acc_valid_in = valid_pipe[CTRL_PIPE_DEPTH-1];
  assign acc_start    = start_pipe[CTRL_PIPE_DEPTH-1];
  assign acc_clear    = clear_pipe[CTRL_PIPE_DEPTH-1];


  // Instantiate
  // Pipelined Multiplier - 3 internal stages, sampled by the accumulator on the 4th clock
  multiplier #(
      .DATA_WIDTH(DATA_WIDTH)
  ) mul_inst (
      .clk(clk),
      .rst_n(rst_n),
      .a_i(mac_a_i),
      .b_i(mac_b_i),
      .product(product_o)
  );

  // Accumulator - Latency: 1 cycle 
  accumulator #(
      .DATA_WIDTH(DATA_WIDTH)
  ) accum_inst (
      .clk(clk),
      .rst_n(rst_n),
      .clear(acc_clear),
      .start(acc_start),
      .valid_i(acc_valid_in),
      // Sign-extend the 34-bit product to 35 bits for the accumulator
      .accum_i({product_o[(DATA_WIDTH*2)-1], product_o}),
      .valid_o(mac_valid_o),
      .accum_o(result)
  );

endmodule
