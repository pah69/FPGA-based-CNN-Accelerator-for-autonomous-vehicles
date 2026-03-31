`timescale 1ns / 1ps
module pe #(
    parameter DATA_WIDTH = 17
) (
    input  logic clk,
    input  logic rst_n,

    // Activation stream for this PE
    input  logic signed [DATA_WIDTH-1:0] activation_i,
    input  logic                         valid_i,

    // Weight load from global buffer
    input  logic signed [DATA_WIDTH-1:0] weight_i,
    input  logic                         weight_load_i,

    // MAC lifecycle control
    input  logic                         start_i,
    input  logic                         clear_i,

    // Observation / result
    output logic signed [2*DATA_WIDTH:0] result_o,
    output logic                         valid_o,
    output logic signed [DATA_WIDTH-1:0] weight_o
);

  logic signed [DATA_WIDTH-1:0] weight_reg;

  // Local stationary weight register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_reg <= '0;
    end else if (weight_load_i) begin
      weight_reg <= weight_i;
    end
  end

  assign weight_o = weight_reg;

  // Existing MAC reused directly
  mac_unit #(
      .DATA_WIDTH(DATA_WIDTH)
  ) mac_inst (
      .clk          (clk),
      .rst_n        (rst_n),
      .mac_a_i      (activation_i),
      .mac_b_i      (weight_reg),
      .mac_valid_i  (valid_i),
      .mac_start    (start_i),
      .mac_acc_clear(clear_i),
      .mac_valid_o  (valid_o),
      .result       (result_o)
  );

endmodule : pe

// // ////////////////////////////////////////////////////////////////////////////////
// // // Company:
// // // Engineer: Anh Ho Pham
// // //
// // // Create Date: 03/03/2026
// // // Design Name: CNN_Accelerator
// // // Module Name: pe (Processing Element)
// // // Target Device: ZCU104
// // // Tool versions: Vivado 2025.2
// // // 
// // ////////////////////////////////////////////////////////////////////////////////

// `timescale 1ns / 1ps
// module pe #(
//     parameter DATA_WIDTH = 17,
//     parameter ADDR_WIDTH = 16,
//     parameter MAC_PIPELINE_DEPTH = 4
// ) (
//     // clock
//     input logic clk,
//     input logic rst_n,

//     // dataflow - Activation
//     input  logic signed [DATA_WIDTH-1:0] activation_i,
//     output logic signed [DATA_WIDTH-1:0] activation_o,

//     // ram ctrl - Weight
//     input logic                         weight_we,
//     input logic        [ADDR_WIDTH-1:0] weight_addr,
//     input logic signed [DATA_WIDTH-1:0] weight_i,

//     // MAC control
//     input logic valid_i,
//     input logic start,
//     input logic acc_clear,

//     // MAC output
//     output logic valid_o,
//     output logic signed [2*DATA_WIDTH:0] result_o
// );

//   // Internal
//   logic signed [DATA_WIDTH-1:0] weight_rd_data;

//   // Array to delay the activation signal
//   logic signed [DATA_WIDTH-1:0] act_pipe[0:MAC_PIPELINE_DEPTH-1];


//   // Instantiations

//   // Local Weight RAM
//   ram #(
//       .ADDR_WIDTH(ADDR_WIDTH),
//       .DATA_WIDTH(DATA_WIDTH),
//       .DEPTH(1 << ADDR_WIDTH)
//   ) ram_inst (
//       .clk    (clk),
//       .cs     (1'b1),
//       .we     (weight_we),
//       .addr   (weight_addr),
//       .wr_data(weight_i),
//       .rd_data(weight_rd_data)
//   );

//   // MAC Unit (3-stage mult + 1-stage acc)
//   mac_unit #(
//       .DATA_WIDTH(DATA_WIDTH)
//   ) mac_inst (
//       .clk          (clk),
//       .rst_n        (rst_n),
//       .mac_a_i      (activation_i),
//       .mac_b_i      (weight_rd_data),
//       .mac_valid_i  (valid_i),
//       .mac_start    (start),
//       .mac_acc_clear(acc_clear),
//       .mac_valid_o  (valid_o),
//       .result       (result_o)
//   );

//   // Delay by 4 clock cycles to match the MACactivation_o
//   always_ff @(posedge clk or negedge rst_n) begin
//     if (!rst_n) begin
//       act_pipe[0] <= '0;
//       act_pipe[1] <= '0;
//       act_pipe[2] <= '0;
//       act_pipe[3] <= '0;
//     end else begin
//       act_pipe[0] <= activation_i;
//       act_pipe[1] <= act_pipe[0];
//       act_pipe[2] <= act_pipe[1];
//       act_pipe[3] <= act_pipe[2];
//     end
//   end

//   // output assign
//   assign activation_o = act_pipe[3];

// endmodule : pe
