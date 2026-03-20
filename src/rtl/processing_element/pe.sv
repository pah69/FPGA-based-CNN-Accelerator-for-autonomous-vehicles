// ////////////////////////////////////////////////////////////////////////////////
// // Company: SoC.one
// // Engineer: Anh Ho Pham
// //
// // Create Date: 03/03/2026
// // Design Name: CNN_Accelerator
// // Module Name: pe (Processing Element)
// // Target Device: ZCU104
// // Tool versions: Vivado 2025.2
// // Description:
// //    Processing Element for systolic array. Integrates an internal BRAM for 
// //    weight storage and a pipelined MAC unit. Forwards activations with a 
// //    matched delay pipeline to maintain array synchronization.
// ////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
module pe #(
    parameter DATA_WIDTH = 17,
    parameter ADDR_WIDTH = 16,
    parameter MAC_PIPELINE_DEPTH = 4
) (
    // clock
    input logic clk,
    input logic rst_n,

    // dataflow (Activation)
    input  logic signed [DATA_WIDTH-1:0] activation_i,
    output logic signed [DATA_WIDTH-1:0] activation_o,

    // ram ctrl (Weight)
    input logic                         weight_we,
    input logic        [ADDR_WIDTH-1:0] weight_addr,
    input logic signed [DATA_WIDTH-1:0] weight_i,

    // MAC control (Lifecycle)
    input logic valid_in,
    input logic start,
    input logic acc_clear,

    // MAC output
    output logic valid_out,
    output logic signed [2*DATA_WIDTH:0] result_o
);

  // --- Internal Signals ---
  logic signed [DATA_WIDTH-1:0] weight_rd_data;

  // Array to delay the activation signal
  logic signed [DATA_WIDTH-1:0] act_pipe[0:MAC_PIPELINE_DEPTH-1];


  // Module Instantiations

  // 1. Local Weight RAM (FPGA BRAM Inferred)
  ram #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH(1 << ADDR_WIDTH)
  ) weight_ram (
      .clk    (clk),
      .cs     (1'b1),           // RAM always selected in this PE
      .we     (weight_we),
      .addr   (weight_addr),
      .wr_data(weight_i),
      .rd_data(weight_rd_data)
  );

  // 2. MAC Unit (3-stage mult + 1-stage acc)
  mac_unit #(
      .DATA_WIDTH(DATA_WIDTH)
  ) mac_inst (
      .clk          (clk),
      .rst_n        (rst_n),
      .mac_a_i      (activation_i),
      .mac_b_i      (weight_rd_data),
      .mac_valid_i  (valid_in),
      .mac_start    (start),
      .mac_acc_clear(acc_clear),
      .mac_valid_o  (valid_out),
      .result       (result_o)
  );

  // Delays the input activation by 4 clock cycles to match the MAC compute path.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_pipe[0] <= '0;
      act_pipe[1] <= '0;
      act_pipe[2] <= '0;
      act_pipe[3] <= '0;
    end else begin
      // Pipeline only advances when valid_in is high
      act_pipe[0] <= activation_i;
      act_pipe[1] <= act_pipe[0];
      act_pipe[2] <= act_pipe[1];
      act_pipe[3] <= act_pipe[2];
    end
  end

  // The output is the last stage of the shift register
  assign activation_o = act_pipe[3];

endmodule : pe



// module pe #(
//     parameter DATA_WIDTH = 17,
//     parameter ADDR_WIDTH = 16,
//     parameter MAC_PIPELINE_DEPTH = 4  // 3 (Mult) + 1 (Acc)
// ) (
//     // clock
//     input logic clk,
//     input logic rst_n,

//     // dataflow (Activation)
//     input  logic signed [DATA_WIDTH-1:0] activation_i,
//     output logic signed [DATA_WIDTH-1:0] activation_o,

//     // ram ctrl (Weight)
//     input logic                         weight_we,
//     input logic        [ADDR_WIDTH-1:0] weight_addr,
//     input logic signed [DATA_WIDTH-1:0] weight_i,

//     // MAC control (Lifecycle)
//     input logic valid_in,
//     input logic start,
//     input logic acc_clear,

//     // MAC output
//     output logic valid_out,
//     output logic signed [2*DATA_WIDTH:0] result_o
// );

//   // --- Internal Signals ---
//   logic signed [DATA_WIDTH-1:0] weight_rd_data;

//   // Shift register array : for delay the activation signal
//   logic signed [DATA_WIDTH-1:0] act_pipe[0:MAC_PIPELINE_DEPTH-1];


//   // --- Instantiations ---

//   // 1. Local Weight RAM (FPGA BRAM Inferred)
//   ram #(
//       .ADDR_WIDTH(ADDR_WIDTH),
//       .DATA_WIDTH(DATA_WIDTH),
//       .DEPTH(1 << ADDR_WIDTH)
//   ) weight_ram (
//       .clk    (clk),
//       .cs     (1'b1),           
//       .we     (weight_we),
//       .addr   (weight_addr),
//       .wr_data(weight_i),
//       .rd_data(weight_rd_data)
//   );

//   // 2. MAC Unit (3-stage mult + 1-stage acc)
//   mac_unit #(
//       .DATA_WIDTH(DATA_WIDTH)
//   ) mac_inst (
//       .clk          (clk),
//       .rst_n        (rst_n),
//       .mac_a_in     (activation_i),
//       .mac_b_in     (weight_rd_data),
//       .mac_valid_in (valid_in),
//       .mac_start    (start),
//       .mac_acc_clear(acc_clear),
//       .mac_valid_out(valid_out),
//       .result       (result_o)
//   );


//   // --- Activation Delay Pipeline ---
//   // Delays the input activation to match the exact latency of the MAC compute path.
//   // This ensures downstream PEs receive the activation in the correct clock cycle.
//   always_ff @(posedge clk or negedge rst_n) begin
//     if (!rst_n) begin
//       for (int i = 0; i < MAC_PIPELINE_DEPTH; i++) begin
//         act_pipe[i] <= '0;
//       end
//     end else begin
//       // Shift data through the pipeline
//       act_pipe[0] <= activation_i;
//       for (int i = 1; i < MAC_PIPELINE_DEPTH; i++) begin
//         act_pipe[i] <= act_pipe[i-1];
//       end
//     end
//   end

//   // The output is the last stage of the shift register
//   assign activation_o = act_pipe[MAC_PIPELINE_DEPTH-1];

// endmodule : pe
