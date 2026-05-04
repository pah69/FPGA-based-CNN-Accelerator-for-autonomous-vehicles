`timescale 1ns / 1ps

module output_accumulator #(
    parameter int SIZE       = 3,
    parameter int LOCAL_PSUM_WIDTH = 21,
    parameter int ACC_WIDTH  = 32,
    parameter int NUM_TILES  = 128
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,

    input logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input logic        [             SIZE-1:0] psum_valid_i,

    output logic signed [(ACC_WIDTH*SIZE)-1:0] result_flatten_o,
    
    output logic                               done_o
);

  logic signed [ACC_WIDTH-1:0] acc[0:SIZE-1];
  logic [$clog2(NUM_TILES+1)-1:0] count[0:SIZE-1];

  integer c;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (c = 0; c < SIZE; c = c + 1) begin
        acc[c]   <= '0;
        count[c] <= '0;
      end
      done_o <= 1'b0;
    end else if (clear_i) begin
      for (c = 0; c < SIZE; c = c + 1) begin
        acc[c]   <= '0;
        count[c] <= '0;
      end
      done_o <= 1'b0;
    end else begin
      for (c = 0; c < SIZE; c = c + 1) begin
        if (psum_valid_i[c] && count[c] < NUM_TILES) begin
          acc[c] <= acc[c] + {{(ACC_WIDTH-LOCAL_PSUM_WIDTH){psum_flatten_i[(c*LOCAL_PSUM_WIDTH)+LOCAL_PSUM_WIDTH-1]}}, psum_flatten_i[(c*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH]};
          count[c] <= count[c] + 1'b1;
        end
      end

      if (psum_valid_i[SIZE-1] && count[SIZE-1] == NUM_TILES - 1) begin
        done_o <= 1'b1;
      end
    end
  end

  genvar i;
  generate
    for (i = 0; i < SIZE; i = i + 1) begin : PACK_RESULT
      assign result_flatten_o[(i*ACC_WIDTH)+:ACC_WIDTH] = acc[i];
    end
  endgenerate

endmodule
