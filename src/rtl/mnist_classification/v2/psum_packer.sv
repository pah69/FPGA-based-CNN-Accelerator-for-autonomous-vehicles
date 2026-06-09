`timescale 1ns / 1ps

// Collects staggered MXU psum lanes into one accumulator row write.
module psum_packer #(
    parameter int SIZE             = 2,
    parameter int LOCAL_PSUM_WIDTH = 18,
    parameter int ADDR_WIDTH       = 4
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,
    input logic capture_en_i,
    input logic [ADDR_WIDTH-1:0] write_addr_i,

    input logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input logic        [                   SIZE-1:0] psum_valid_i,

    output logic                                      packed_valid_o,
    output logic        [             ADDR_WIDTH-1:0] packed_write_addr_o,
    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] packed_psum_flatten_o,
    output logic        [                   SIZE-1:0] packed_psum_valid_o,
    output logic                                      busy_o
);

  logic        [                   SIZE-1:0] lane_valid_q;
  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] lane_data_q;

  logic        [                   SIZE-1:0] accepted_valid_w;
  logic        [                   SIZE-1:0] merged_valid_w;
  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] merged_data_w;
  logic        [             ADDR_WIDTH-1:0] merged_addr_w;
  logic                                      complete_w;

  assign accepted_valid_w = capture_en_i ? psum_valid_i : '0;
  assign merged_valid_w   = lane_valid_q | accepted_valid_w;
  assign merged_addr_w    = (|lane_valid_q) ? packed_write_addr_o : write_addr_i;
  assign complete_w       = &merged_valid_w;
  assign busy_o           = |lane_valid_q;

  always_comb begin
    merged_data_w = lane_data_q;
    for (int lane = 0; lane < SIZE; lane++) begin
      if (accepted_valid_w[lane]) begin
        merged_data_w[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] =
            psum_flatten_i[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lane_valid_q          <= '0;
      lane_data_q           <= '0;
      packed_valid_o        <= 1'b0;
      packed_write_addr_o   <= '0;
      packed_psum_flatten_o <= '0;
      packed_psum_valid_o   <= '0;
    end else if (clear_i) begin
      lane_valid_q          <= '0;
      lane_data_q           <= '0;
      packed_valid_o        <= 1'b0;
      packed_write_addr_o   <= '0;
      packed_psum_flatten_o <= '0;
      packed_psum_valid_o   <= '0;
    end else begin
      packed_valid_o      <= 1'b0;
      packed_psum_valid_o <= '0;

      if (capture_en_i && (|psum_valid_i) && !(|lane_valid_q)) begin
        packed_write_addr_o <= write_addr_i;
      end

      if (complete_w && (|merged_valid_w)) begin
        lane_valid_q          <= '0;
        lane_data_q           <= '0;
        packed_valid_o        <= 1'b1;
        packed_write_addr_o   <= merged_addr_w;
        packed_psum_flatten_o <= merged_data_w;
        packed_psum_valid_o   <= '1;
      end else begin
        lane_valid_q <= merged_valid_w;
        lane_data_q  <= merged_data_w;
      end
    end
  end

endmodule : psum_packer_v2
