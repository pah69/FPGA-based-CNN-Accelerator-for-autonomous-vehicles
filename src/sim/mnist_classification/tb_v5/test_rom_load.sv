`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

module test_rom_load;

  localparam int DATA_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int MULT_WIDTH = 32;
  localparam int SHIFT_WIDTH = 6;
  localparam int WGT_DEPTH = 4952;
  localparam int PARAM_DEPTH = 44;
  localparam int WGT_ADDR_WIDTH = $clog2(WGT_DEPTH);
  localparam int PARAM_ADDR_WIDTH = $clog2(PARAM_DEPTH);
  localparam int CLK_PERIOD = 10;

  logic clk;
  logic rst_n;

  logic wgt_en_i;
  logic [WGT_ADDR_WIDTH-1:0] wgt_addr_i;
  logic signed [DATA_WIDTH-1:0] wgt_data_o;
  logic wgt_valid_o;

  logic bias_en_i;
  logic [PARAM_ADDR_WIDTH-1:0] bias_addr_i;
  logic signed [BIAS_WIDTH-1:0] bias_data_o;
  logic bias_valid_o;

  logic mult_en_i;
  logic [PARAM_ADDR_WIDTH-1:0] mult_addr_i;
  logic signed [MULT_WIDTH-1:0] mult_data_o;
  logic mult_valid_o;

  logic shift_en_i;
  logic [PARAM_ADDR_WIDTH-1:0] shift_addr_i;
  logic [SHIFT_WIDTH-1:0] shift_data_o;
  logic shift_valid_o;

  logic [1:0] layer_idx_i;
  logic desc_valid_o;
  layer_type_t desc_layer_type_o;
  logic [15:0] desc_in_h_o;
  logic [15:0] desc_in_w_o;
  logic [15:0] desc_in_ch_o;
  logic [15:0] desc_out_h_o;
  logic [15:0] desc_out_w_o;
  logic [15:0] desc_out_ch_o;
  logic [15:0] desc_kernel_h_o;
  logic [15:0] desc_kernel_w_o;
  logic [15:0] desc_k_total_o;
  logic [15:0] desc_num_k_tiles_o;
  logic [15:0] desc_num_oc_tiles_o;
  logic [15:0] desc_num_spatial_o;
  logic [15:0] desc_weight_base_o;
  logic [15:0] desc_bias_base_o;
  logic [15:0] desc_requant_base_o;
  act_mode_t desc_act_mode_o;
  logic desc_read_bank_o;
  logic desc_write_bank_o;

  int test_count;
  int pass_count;
  int fail_count;

  weight_rom #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH     (WGT_DEPTH),
      .ADDR_WIDTH(WGT_ADDR_WIDTH)
  ) u_weight_rom (
      .clk    (clk),
      .rst_n  (rst_n),
      .en_i   (wgt_en_i),
      .addr_i (wgt_addr_i),
      .data_o (wgt_data_o),
      .valid_o(wgt_valid_o)
  );

  bias_rom #(
      .DATA_WIDTH(BIAS_WIDTH),
      .DEPTH     (PARAM_DEPTH),
      .ADDR_WIDTH(PARAM_ADDR_WIDTH)
  ) u_bias_rom (
      .clk    (clk),
      .rst_n  (rst_n),
      .en_i   (bias_en_i),
      .addr_i (bias_addr_i),
      .data_o (bias_data_o),
      .valid_o(bias_valid_o)
  );

  requant_mult_rom #(
      .DATA_WIDTH(MULT_WIDTH),
      .DEPTH     (PARAM_DEPTH),
      .ADDR_WIDTH(PARAM_ADDR_WIDTH)
  ) u_requant_mult_rom (
      .clk    (clk),
      .rst_n  (rst_n),
      .en_i   (mult_en_i),
      .addr_i (mult_addr_i),
      .data_o (mult_data_o),
      .valid_o(mult_valid_o)
  );

  requant_shift_rom #(
      .DATA_WIDTH(SHIFT_WIDTH),
      .DEPTH     (PARAM_DEPTH),
      .ADDR_WIDTH(PARAM_ADDR_WIDTH)
  ) u_requant_shift_rom (
      .clk    (clk),
      .rst_n  (rst_n),
      .en_i   (shift_en_i),
      .addr_i (shift_addr_i),
      .data_o (shift_data_o),
      .valid_o(shift_valid_o)
  );

  layer_descriptor_rom u_layer_descriptor_rom (
      .layer_idx_i    (layer_idx_i),
      .valid_o        (desc_valid_o),
      .layer_type_o   (desc_layer_type_o),
      .in_h_o         (desc_in_h_o),
      .in_w_o         (desc_in_w_o),
      .in_ch_o        (desc_in_ch_o),
      .out_h_o        (desc_out_h_o),
      .out_w_o        (desc_out_w_o),
      .out_ch_o       (desc_out_ch_o),
      .kernel_h_o     (desc_kernel_h_o),
      .kernel_w_o     (desc_kernel_w_o),
      .k_total_o      (desc_k_total_o),
      .num_k_tiles_o  (desc_num_k_tiles_o),
      .num_oc_tiles_o (desc_num_oc_tiles_o),
      .num_spatial_o  (desc_num_spatial_o),
      .weight_base_o  (desc_weight_base_o),
      .bias_base_o    (desc_bias_base_o),
      .requant_base_o (desc_requant_base_o),
      .act_mode_o     (desc_act_mode_o),
      .read_bank_o    (desc_read_bank_o),
      .write_bank_o   (desc_write_bank_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  task automatic print_header(input string title);
    $display("");
    $display("============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

  task automatic expect_flag(input string label, input logic condition);
    test_count++;
    if (condition) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s", label);
    end
  endtask

  task automatic expect_i8(
      input string label,
      input logic signed [DATA_WIDTH-1:0] actual,
      input logic signed [DATA_WIDTH-1:0] expected
  );
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic expect_i32(
      input string label,
      input logic signed [31:0] actual,
      input logic signed [31:0] expected
  );
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic expect_u32(
      input string label,
      input logic [31:0] actual,
      input logic [31:0] expected
  );
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, actual, expected);
    end
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    wgt_en_i = 1'b0;
    bias_en_i = 1'b0;
    mult_en_i = 1'b0;
    shift_en_i = 1'b0;
    wgt_addr_i = '0;
    bias_addr_i = '0;
    mult_addr_i = '0;
    shift_addr_i = '0;
    layer_idx_i = '0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
  endtask

  task automatic read_weight(
      input int unsigned addr,
      input logic signed [DATA_WIDTH-1:0] expected
  );
    @(negedge clk);
    wgt_addr_i = WGT_ADDR_WIDTH'(addr);
    wgt_en_i = 1'b1;
    @(posedge clk);
    #1;
    $display("  weight[%0d] = %0d", addr, $signed(wgt_data_o));
    expect_flag($sformatf("weight[%0d] valid", addr), wgt_valid_o);
    expect_i8($sformatf("weight[%0d]", addr), wgt_data_o, expected);
    @(negedge clk);
    wgt_en_i = 1'b0;
  endtask

  task automatic read_bias(
      input int unsigned addr,
      input logic signed [BIAS_WIDTH-1:0] expected
  );
    @(negedge clk);
    bias_addr_i = PARAM_ADDR_WIDTH'(addr);
    bias_en_i = 1'b1;
    @(posedge clk);
    #1;
    $display("  bias[%0d] = %0d", addr, $signed(bias_data_o));
    expect_flag($sformatf("bias[%0d] valid", addr), bias_valid_o);
    expect_i32($sformatf("bias[%0d]", addr), bias_data_o, expected);
    @(negedge clk);
    bias_en_i = 1'b0;
  endtask

  task automatic read_mult(
      input int unsigned addr,
      input logic signed [MULT_WIDTH-1:0] expected
  );
    @(negedge clk);
    mult_addr_i = PARAM_ADDR_WIDTH'(addr);
    mult_en_i = 1'b1;
    @(posedge clk);
    #1;
    $display("  requant_mult[%0d] = %0d", addr, $signed(mult_data_o));
    expect_flag($sformatf("requant_mult[%0d] valid", addr), mult_valid_o);
    expect_i32($sformatf("requant_mult[%0d]", addr), mult_data_o, expected);
    @(negedge clk);
    mult_en_i = 1'b0;
  endtask

  task automatic read_shift(
      input int unsigned addr,
      input logic [SHIFT_WIDTH-1:0] expected
  );
    @(negedge clk);
    shift_addr_i = PARAM_ADDR_WIDTH'(addr);
    shift_en_i = 1'b1;
    @(posedge clk);
    #1;
    $display("  requant_shift[%0d] = %0d", addr, shift_data_o);
    expect_flag($sformatf("requant_shift[%0d] valid", addr), shift_valid_o);
    expect_u32($sformatf("requant_shift[%0d]", addr), 32'(shift_data_o), 32'(expected));
    @(negedge clk);
    shift_en_i = 1'b0;
  endtask

  task automatic check_descriptor(
      input logic [1:0] layer_idx,
      input layer_type_t expected_type,
      input logic [15:0] expected_k_total,
      input logic [15:0] expected_num_k_tiles,
      input logic [15:0] expected_num_oc_tiles,
      input logic [15:0] expected_num_spatial,
      input logic [15:0] expected_weight_base,
      input logic [15:0] expected_bias_base,
      input act_mode_t expected_act_mode,
      input logic expected_read_bank,
      input logic expected_write_bank
  );
    layer_idx_i = layer_idx;
    #1;
    $display("  desc[%0d]: K=%0d k_tiles=%0d oc_tiles=%0d spatial=%0d weight_base=%0d bias_base=%0d act=%0d",
             layer_idx, desc_k_total_o, desc_num_k_tiles_o, desc_num_oc_tiles_o,
             desc_num_spatial_o, desc_weight_base_o, desc_bias_base_o, desc_act_mode_o);
    expect_flag($sformatf("descriptor[%0d] valid", layer_idx), desc_valid_o);
    expect_flag($sformatf("descriptor[%0d] layer type", layer_idx),
                desc_layer_type_o == expected_type);
    expect_u32($sformatf("descriptor[%0d] K total", layer_idx),
               32'(desc_k_total_o), 32'(expected_k_total));
    expect_u32($sformatf("descriptor[%0d] K tiles", layer_idx),
               32'(desc_num_k_tiles_o), 32'(expected_num_k_tiles));
    expect_u32($sformatf("descriptor[%0d] OC tiles", layer_idx),
               32'(desc_num_oc_tiles_o), 32'(expected_num_oc_tiles));
    expect_u32($sformatf("descriptor[%0d] spatial", layer_idx),
               32'(desc_num_spatial_o), 32'(expected_num_spatial));
    expect_u32($sformatf("descriptor[%0d] weight base", layer_idx),
               32'(desc_weight_base_o), 32'(expected_weight_base));
    expect_u32($sformatf("descriptor[%0d] bias base", layer_idx),
               32'(desc_bias_base_o), 32'(expected_bias_base));
    expect_flag($sformatf("descriptor[%0d] activation", layer_idx),
                desc_act_mode_o == expected_act_mode);
    expect_flag($sformatf("descriptor[%0d] read bank", layer_idx),
                desc_read_bank_o == expected_read_bank);
    expect_flag($sformatf("descriptor[%0d] write bank", layer_idx),
                desc_write_bank_o == expected_write_bank);
  endtask

  initial begin
    reset_dut();

    print_header("TEST: Weight ROM boundary offsets");
    read_weight(0, 8'sd127);
    read_weight(71, -8'sd14);
    read_weight(72, -8'sd7);
    read_weight(791, -8'sd48);
    read_weight(792, 8'sd23);
    read_weight(4791, -8'sd49);
    read_weight(4792, -8'sd121);
    read_weight(4951, 8'sd127);

    print_header("TEST: Bias and requant base offsets");
    read_bias(0, -32'sd2384);
    read_bias(8, -32'sd378);
    read_bias(18, -32'sd73);
    read_bias(34, -32'sd609);

    read_mult(0, 32'sd1795188);
    read_mult(8, 32'sd9065232);
    read_mult(18, 32'sd3026578);
    read_mult(34, 32'sd7878581);

    read_shift(0, 6'd31);
    read_shift(8, 6'd31);
    read_shift(18, 6'd31);
    read_shift(34, 6'd31);

    print_header("TEST: Layer descriptor ROM");
    check_descriptor(LAYER_IDX_CONV1, LAYER_CONV, 16'd9, 16'd5, 16'd4, 16'd676,
                     16'd0, 16'd0, ACT_RELU, 1'b0, 1'b1);
    check_descriptor(LAYER_IDX_CONV2, LAYER_CONV, 16'd72, 16'd36, 16'd5, 16'd121,
                     16'd72, 16'd8, ACT_RELU, 1'b0, 1'b1);
    check_descriptor(LAYER_IDX_FC1, LAYER_FC, 16'd250, 16'd125, 16'd8, 16'd1,
                     16'd792, 16'd18, ACT_RELU, 1'b0, 1'b1);
    check_descriptor(LAYER_IDX_FC2, LAYER_FC, 16'd16, 16'd8, 16'd5, 16'd1,
                     16'd4792, 16'd34, ACT_BYPASS, 1'b1, 1'b0);

    $display("test_rom_load: checks=%0d pass=%0d fail=%0d", test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_rom_load failed");
    end
    $finish;
  end

endmodule : test_rom_load
