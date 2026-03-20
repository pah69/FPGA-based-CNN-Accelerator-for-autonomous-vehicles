////////////////////////////////////////////////////////////////////////////////
// Company: <Company Name>
// Engineer: Anh Ho Pham
//
// Create Date: 03/03/2026
// Design Name: MAC_unit
// Module Name: multiplier
// Target Device: ZCU104
// Tool versions: Vivado 2025.2
// Description:
//    <Description here>
// Dependencies:
//    <Dependencies here>
// Revision:
//    <Code_revision_information>
// Additional Comments:
//    <Additional_comments>
////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module multiplier #(
    parameter DATA_WIDTH = 17
) (
    input  logic clk,
    input  logic rst_n,
    input  logic signed [DATA_WIDTH-1:0] a_in,
    input  logic signed [DATA_WIDTH-1:0] b_in,
    output logic signed [(2*DATA_WIDTH)-1:0] product
);

    // Stage 1: Input registers
    logic signed [DATA_WIDTH-1:0]     a_reg;
    logic signed [DATA_WIDTH-1:0]     b_reg;
    
    // Stage 2: Multiplication result register
    logic signed [(2*DATA_WIDTH)-1:0] mult_reg;
    
    // Stage 3: Output register
    logic signed [(2*DATA_WIDTH)-1:0] product_reg;

    // --- Pipeline Implementation ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all pipeline stages
            a_reg       <= '0;
            b_reg       <= '0;
            mult_reg    <= '0;
            product_reg <= '0;
        end else begin
            // Stage 1: Latch the inputs
            a_reg       <= a_in;
            b_reg       <= b_in;
            
            // Stage 2: Perform multiplication on registered inputs
            mult_reg    <= $signed(a_reg) * $signed(b_reg);
            
            // Stage 3: Latch the final product
            product_reg <= mult_reg;
        end
    end

    // Assign the final registered output to the port
    assign product = product_reg;

endmodule

  // localparam HALF_WIDTH = DATA_WIDTH / 2;
  // localparam HI_WIDTH = DATA_WIDTH - HALF_WIDTH;  // 9
  // // --- Stage 1: Input Registration & Split ---
  // // logic [HALF_WIDTH-1:0] a_hi, a_lo;
  // logic signed [HI_WIDTH-1:0] a_hi, b_hi;  // 9 bits
  // logic signed [HALF_WIDTH-1:0] a_lo, b_lo;  // 8 bits

  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //     a_hi <= '0;
  //     a_lo <= '0;
  //     b_hi <= '0;
  //     b_lo <= '0;
  //   end else begin
  //     a_hi <= a_in[DATA_WIDTH-1:HALF_WIDTH];
  //     a_lo <= a_in[HALF_WIDTH-1:0];
  //     b_hi <= b_in[DATA_WIDTH-1:HALF_WIDTH];
  //     b_lo <= b_in[HALF_WIDTH-1:0];
  //   end
  // end

  // // --- Stage 2: Partial Products (16x16 multiply) ---
  // // These are much smaller and faster than a 32x32 mult
  // logic [(2*HALF_WIDTH)-1:0] pp_hh, pp_hl, pp_lh, pp_ll;

  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //     pp_hh <= '0;
  //     pp_hl <= '0;
  //     pp_lh <= '0;
  //     pp_ll <= '0;
  //   end else begin
  //     pp_hh <= a_hi * b_hi;
  //     pp_hl <= a_hi * b_lo;
  //     pp_lh <= a_lo * b_hi;
  //     pp_ll <= a_lo * b_lo;
  //   end
  // end

  // // --- Stage 3: Middle Addition ---
  // // Sum the middle terms: (AH * BL) + (AL * BH)
  // logic [(2*DATA_WIDTH)-1:0] sum_mid;
  // logic [(2*DATA_WIDTH)-1:0] pp_hh_reg, pp_ll_reg;  // Pipeline alignment

  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //     sum_mid   <= '0;
  //     pp_hh_reg <= '0;
  //     pp_ll_reg <= '0;
  //   end else begin
  //     // Add middle terms
  //     sum_mid   <= pp_hl + pp_lh;

  //     // Pass the High and Low parts forward to stay in sync
  //     pp_hh_reg <= pp_hh;
  //     pp_ll_reg <= pp_ll;
  //   end
  // end

  // // --- Stage 4: Final Summation ---
  // // Combine: (HH << 32) + (Mid << 16) + LL
  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //     product <= '0;
  //   end else begin
  //     //   product <= (pp_hh_reg << DATA_WIDTH) + (sum_mid << HALF_WIDTH) + pp_ll_reg;
  //     // Shift by HALF_WIDTH*2 (16), not DATA_WIDTH (17)
  //     product <= (pp_hh_reg << (HALF_WIDTH * 2)) + (sum_mid << HALF_WIDTH) + pp_ll_reg;
  //   end
  // end