`timescale 1ns / 1ps

module systolic_array_4x4 #(
    parameter int DATA_WIDTH = 17,
    parameter int PSUM_WIDTH = (2 * DATA_WIDTH) + 8
) (
    input logic clk,
    input logic rst_n,

    // row acts
    input logic signed [(4*DATA_WIDTH)-1:0] act_in_flat,
    input logic                             act_valid_i,

    // top wgts
    input logic signed [(4*DATA_WIDTH)-1:0] wgt_in_flat,
    input logic                             wgt_ld_i,

    // bottom outs
    output logic signed [(4*PSUM_WIDTH)-1:0] out_flat,
    output logic        [               3:0] out_valid
);

  // input 
  logic signed [DATA_WIDTH-1:0] act0_i, act1_i, act2_i, act3_i;
  logic signed [DATA_WIDTH-1:0] wgt0_i, wgt1_i, wgt2_i, wgt3_i;

  // weight load by row
  logic ld0, ld1, ld2, ld3;

  // zero psum
  logic signed [PSUM_WIDTH-1:0] psum_0;

  // activation links
  logic signed [DATA_WIDTH-1:0] activation_00, activation_01, activation_02;
  logic signed [DATA_WIDTH-1:0] activation_10, activation_11, activation_12;
  logic signed [DATA_WIDTH-1:0] activation_20, activation_21, activation_22;
  logic signed [DATA_WIDTH-1:0] activation_30, activation_31, activation_32;

  logic activation_valid_00, activation_valid_01, activation_valid_02;
  logic activation_valid_10, activation_valid_11, activation_valid_12;
  logic activation_valid_20, activation_valid_21, activation_valid_22;
  logic activation_valid_30, activation_valid_31, activation_valid_32;
    
  // psum links
  logic signed [PSUM_WIDTH-1:0] psum_00, psum_01, psum_02, psum_03;
  logic signed [PSUM_WIDTH-1:0] psum_10, psum_11, psum_12, psum_13;
  logic signed [PSUM_WIDTH-1:0] psum_20, psum_21, psum_22, psum_23;
  logic signed [PSUM_WIDTH-1:0] psum_30, psum_31, psum_32, psum_33;

  logic psum_valid_00, psum_valid_01, psum_valid_02, psum_valid_03;
  logic psum_valid_10, psum_valid_11, psum_valid_12, psum_valid_13;
  logic psum_valid_20, psum_valid_21, psum_valid_22, psum_valid_23;
  logic psum_valid_30, psum_valid_31, psum_valid_32, psum_valid_33;

  // weight links
  logic signed [DATA_WIDTH-1:0] weight_00, weight_01, weight_02, weight_03;
  logic signed [DATA_WIDTH-1:0] weight_10, weight_11, weight_12, weight_13;
  logic signed [DATA_WIDTH-1:0] weight_20, weight_21, weight_22, weight_23;
  logic signed [DATA_WIDTH-1:0] weight_30, weight_31, weight_32, weight_33;

  assign psum_0 = '0;

  assign act0_i = act_in_flat[(0*DATA_WIDTH)+:DATA_WIDTH];
  assign act1_i = act_in_flat[(1*DATA_WIDTH)+:DATA_WIDTH];
  assign act2_i = act_in_flat[(2*DATA_WIDTH)+:DATA_WIDTH];
  assign act3_i = act_in_flat[(3*DATA_WIDTH)+:DATA_WIDTH];

  assign wgt0_i = wgt_in_flat[(0*DATA_WIDTH)+:DATA_WIDTH];
  assign wgt1_i = wgt_in_flat[(1*DATA_WIDTH)+:DATA_WIDTH];
  assign wgt2_i = wgt_in_flat[(2*DATA_WIDTH)+:DATA_WIDTH];
  assign wgt3_i = wgt_in_flat[(3*DATA_WIDTH)+:DATA_WIDTH];

  // shift load down
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ld0 <= 1'b0;
      ld1 <= 1'b0;
      ld2 <= 1'b0;
      ld3 <= 1'b0;
    end else begin
      ld0 <= wgt_ld_i;
      ld1 <= ld0;
      ld2 <= ld1;
      ld3 <= ld2;
    end
  end

  // row 0
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe00 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act0_i),
      .act_valid_i  (act_valid_i),
      .psum_i       (psum_0),
      .psum_valid_i (1'b1),
      .weight_i     (wgt0_i),
      .weight_load_i(ld0),
      .act_o        (activation_00),
      .act_valid_o  (activation_valid_00),
      .psum_o       (psum_00),
      .psum_valid_o (psum_valid_00),
      .weight_o     (weight_00)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe01 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_00),
      .act_valid_i  (activation_valid_00),
      .psum_i       (psum_0),
      .psum_valid_i (1'b1),
      .weight_i     (wgt1_i),
      .weight_load_i(ld0),
      .act_o        (activation_01),
      .act_valid_o  (activation_valid_01),
      .psum_o       (psum_01),
      .psum_valid_o (psum_valid_01),
      .weight_o     (weight_01)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe02 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_01),
      .act_valid_i  (activation_valid_01),
      .psum_i       (psum_0),
      .psum_valid_i (1'b1),
      .weight_i     (wgt2_i),
      .weight_load_i(ld0),
      .act_o        (activation_02),
      .act_valid_o  (activation_valid_02),
      .psum_o       (psum_02),
      .psum_valid_o (psum_valid_02),
      .weight_o     (weight_02)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe03 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_02),
      .act_valid_i  (activation_valid_02),
      .psum_i       (psum_0),
      .psum_valid_i (1'b1),
      .weight_i     (wgt3_i),
      .weight_load_i(ld0),
      .act_o        (),
      .act_valid_o  (),
      .psum_o       (psum_03),
      .psum_valid_o (psum_valid_03),
      .weight_o     (weight_03)
  );

  // row 1
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe10 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act1_i),
      .act_valid_i  (act_valid_i),
      .psum_i       (psum_00),
      .psum_valid_i (psum_valid_00),
      .weight_i     (weight_00),
      .weight_load_i(ld1),
      .act_o        (activation_10),
      .act_valid_o  (activation_valid_10),
      .psum_o       (psum_10),
      .psum_valid_o (psum_valid_10),
      .weight_o     (weight_10)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe11 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_10),
      .act_valid_i  (activation_valid_10),
      .psum_i       (psum_01),
      .psum_valid_i (psum_valid_01),
      .weight_i     (weight_01),
      .weight_load_i(ld1),
      .act_o        (activation_11),
      .act_valid_o  (activation_valid_11),
      .psum_o       (psum_11),
      .psum_valid_o (psum_valid_11),
      .weight_o     (weight_11)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe12 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_11),
      .act_valid_i  (activation_valid_11),
      .psum_i       (psum_02),
      .psum_valid_i (psum_valid_02),
      .weight_i     (weight_02),
      .weight_load_i(ld1),
      .act_o        (activation_12),
      .act_valid_o  (activation_valid_12),
      .psum_o       (psum_12),
      .psum_valid_o (psum_valid_12),
      .weight_o     (weight_12)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe13 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_12),
      .act_valid_i  (activation_valid_12),
      .psum_i       (psum_03),
      .psum_valid_i (psum_valid_03),
      .weight_i     (weight_03),
      .weight_load_i(ld1),
      .act_o        (),
      .act_valid_o  (),
      .psum_o       (psum_13),
      .psum_valid_o (psum_valid_13),
      .weight_o     (weight_13)
  );

  // row 2
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe20 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act2_i),
      .act_valid_i  (act_valid_i),
      .psum_i       (psum_10),
      .psum_valid_i (psum_valid_10),
      .weight_i     (weight_10),
      .weight_load_i(ld2),
      .act_o        (activation_20),
      .act_valid_o  (activation_valid_20),
      .psum_o       (psum_20),
      .psum_valid_o (psum_valid_20),
      .weight_o     (weight_20)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe21 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_20),
      .act_valid_i  (activation_valid_20),
      .psum_i       (psum_11),
      .psum_valid_i (psum_valid_11),
      .weight_i     (weight_11),
      .weight_load_i(ld2),
      .act_o        (activation_21),
      .act_valid_o  (activation_valid_21),
      .psum_o       (psum_21),
      .psum_valid_o (psum_valid_21),
      .weight_o     (weight_21)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe22 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_21),
      .act_valid_i  (activation_valid_21),
      .psum_i       (psum_12),
      .psum_valid_i (psum_valid_12),
      .weight_i     (weight_12),
      .weight_load_i(ld2),
      .act_o        (activation_22),
      .act_valid_o  (activation_valid_22),
      .psum_o       (psum_22),
      .psum_valid_o (psum_valid_22),
      .weight_o     (weight_22)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe23 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_22),
      .act_valid_i  (activation_valid_22),
      .psum_i       (psum_13),
      .psum_valid_i (psum_valid_13),
      .weight_i     (weight_13),
      .weight_load_i(ld2),
      .act_o        (),
      .act_valid_o  (),
      .psum_o       (psum_23),
      .psum_valid_o (psum_valid_23),
      .weight_o     (weight_23)
  );

  // row 3
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe30 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act3_i),
      .act_valid_i  (act_valid_i),
      .psum_i       (psum_20),
      .psum_valid_i (psum_valid_20),
      .weight_i     (weight_20),
      .weight_load_i(ld3),
      .act_o        (activation_30),
      .act_valid_o  (activation_valid_30),
      .psum_o       (psum_30),
      .psum_valid_o (psum_valid_30),
      .weight_o     (weight_30)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe31 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_30),
      .act_valid_i  (activation_valid_30),
      .psum_i       (psum_21),
      .psum_valid_i (psum_valid_21),
      .weight_i     (weight_21),
      .weight_load_i(ld3),
      .act_o        (activation_31),
      .act_valid_o  (activation_valid_31),
      .psum_o       (psum_31),
      .psum_valid_o (psum_valid_31),
      .weight_o     (weight_31)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe32 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_31),
      .act_valid_i  (activation_valid_31),
      .psum_i       (psum_22),
      .psum_valid_i (psum_valid_22),
      .weight_i     (weight_22),
      .weight_load_i(ld3),
      .act_o        (activation_32),
      .act_valid_o  (activation_valid_32),
      .psum_o       (psum_32),
      .psum_valid_o (psum_valid_32),
      .weight_o     (weight_32)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe33 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (activation_32),
      .act_valid_i  (activation_valid_32),
      .psum_i       (psum_23),
      .psum_valid_i (psum_valid_23),
      .weight_i     (weight_23),
      .weight_load_i(ld3),
      .act_o        (),
      .act_valid_o  (),
      .psum_o       (psum_33),
      .psum_valid_o (psum_valid_33),
      .weight_o     (weight_33)
  );

  // pack out
  assign out_flat[(0*PSUM_WIDTH)+:PSUM_WIDTH] = psum_30;
  assign out_flat[(1*PSUM_WIDTH)+:PSUM_WIDTH] = psum_31;
  assign out_flat[(2*PSUM_WIDTH)+:PSUM_WIDTH] = psum_32;
  assign out_flat[(3*PSUM_WIDTH)+:PSUM_WIDTH] = psum_33;

  assign out_valid[0] = psum_valid_30;
  assign out_valid[1] = psum_valid_31;
  assign out_valid[2] = psum_valid_32;
  assign out_valid[3] = psum_valid_33;

endmodule
