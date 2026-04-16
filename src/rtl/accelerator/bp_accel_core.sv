`timescale 1ns / 1ps

module bp_accelerator_core (
    input logic clk,
    input logic rst_n
);


  // -------------------------------------------------------------------------
  // Internal wiring
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Input buffer (Global buffer)
  // -------------------------------------------------------------------------
  bp_input_buffer #(.DATA_WIDTH(DATA_WIDTH)) u_bp_input_buffer (.clk(clk));

  // -------------------------------------------------------------------------
  // Output buffer (Global buffer)
  // -------------------------------------------------------------------------
  bp_output_buffer #(.DATA_WIDTH(DATA_WIDTH)) u_bp_output_buffer (.clk(clk));

  // -------------------------------------------------------------------------
  // Compute engine
  // -------------------------------------------------------------------------
  bp_compute_engine #(
      .DATA_WIDTH(DATA_WIDTH)
  ) u_bp_compute_engine (
      .clk  (clk),
      .rst_n(rst_n)
  );


  // -------------------------------------------------------------------------
  // Controller
  // -------------------------------------------------------------------------
  bp_controller #(
      .DATA_WIDTH(DATA_WIDTH)
  ) u_bp_controller (
      .clk  (clk),
      .rst_n(rst_n)
  );
endmodule : bp_accelerator_core
