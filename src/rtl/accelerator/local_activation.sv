`timescale 1ns / 1ps

module local_activation #(
    parameter int DATA_WIDTH = 17,
    parameter int ROWS       = 4
) (
    input  logic clk,
    input  logic rst_n,

    // Load one activation vector from activation_buffer.
    // Packing convention:
    //   act_vec_i[(r+1)*DATA_WIDTH-1 -: DATA_WIDTH] = activation for row r
    input  logic                         load_i,
    input  logic [ROWS*DATA_WIDTH-1:0]  act_vec_i,

    // Control aligned with the activation vector.
    input  logic                         act_valid_i,
    input  logic                         start_i,
    input  logic                         clear_i,

    // Registered outputs that drive the systolic array.
    output logic signed [DATA_WIDTH-1:0] act_out   [0:ROWS-1],
    output logic                         valid_out,
    output logic                         start_out,
    output logic                         clear_out
);

  integer r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (r = 0; r < ROWS; r++) begin
        act_out[r] <= '0;
      end
      valid_out <= 1'b0;
      start_out <= 1'b0;
      clear_out <= 1'b0;
    end else begin
      // Control signals are pulses aligned to the current load event.
      valid_out <= 1'b0;
      start_out <= 1'b0;
      clear_out <= 1'b0;

      if (load_i) begin
        for (r = 0; r < ROWS; r++) begin
          act_out[r] <= act_vec_i[(r*DATA_WIDTH) +: DATA_WIDTH];
        end
        valid_out <= act_valid_i;
        start_out <= start_i;
        clear_out <= clear_i;
      end
    end
  end

endmodule : local_activation