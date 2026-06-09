`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

module test_conv_fc_address_generator;

  localparam int SIZE = 2;
  localparam int ADDR_WIDTH = 16;
  localparam int DIM_WIDTH = 16;

  logic [1:0] layer_type_i;
  logic [ADDR_WIDTH-1:0] activation_base_addr_i;
  logic [ADDR_WIDTH-1:0] weight_base_addr_i;
  logic [DIM_WIDTH-1:0] in_h_i;
  logic [DIM_WIDTH-1:0] in_w_i;
  logic [DIM_WIDTH-1:0] out_w_i;
  logic [DIM_WIDTH-1:0] out_ch_i;
  logic [DIM_WIDTH-1:0] kernel_h_i;
  logic [DIM_WIDTH-1:0] kernel_w_i;
  logic [DIM_WIDTH-1:0] k_total_i;
  logic [DIM_WIDTH-1:0] spatial_idx_i;
  logic [DIM_WIDTH-1:0] k_tile_idx_i;
  logic [DIM_WIDTH-1:0] oc_tile_idx_i;

  logic [ADDR_WIDTH*SIZE-1:0] act_addr_flatten_o;
  logic [SIZE-1:0] act_valid_o;
  logic [SIZE-1:0] act_zero_o;
  logic [ADDR_WIDTH*SIZE*SIZE-1:0] weight_addr_flatten_o;
  logic [SIZE*SIZE-1:0] weight_valid_o;
  logic [SIZE*SIZE-1:0] weight_zero_o;
  logic [DIM_WIDTH*SIZE-1:0] k_index_flatten_o;
  logic [DIM_WIDTH*SIZE-1:0] oc_index_flatten_o;

  int test_count;
  int pass_count;
  int fail_count;

  conv_fc_address_generator #(
      .SIZE      (SIZE),
      .ADDR_WIDTH(ADDR_WIDTH),
      .DIM_WIDTH (DIM_WIDTH)
  ) dut (
      .layer_type_i        (layer_type_i),
      .activation_base_addr_i(activation_base_addr_i),
      .weight_base_addr_i  (weight_base_addr_i),
      .in_h_i              (in_h_i),
      .in_w_i              (in_w_i),
      .out_w_i             (out_w_i),
      .out_ch_i            (out_ch_i),
      .kernel_h_i          (kernel_h_i),
      .kernel_w_i          (kernel_w_i),
      .k_total_i           (k_total_i),
      .spatial_idx_i       (spatial_idx_i),
      .k_tile_idx_i        (k_tile_idx_i),
      .oc_tile_idx_i       (oc_tile_idx_i),
      .act_addr_flatten_o  (act_addr_flatten_o),
      .act_valid_o         (act_valid_o),
      .act_zero_o          (act_zero_o),
      .weight_addr_flatten_o(weight_addr_flatten_o),
      .weight_valid_o      (weight_valid_o),
      .weight_zero_o       (weight_zero_o),
      .k_index_flatten_o   (k_index_flatten_o),
      .oc_index_flatten_o  (oc_index_flatten_o)
  );

  function automatic logic [ADDR_WIDTH-1:0] act_addr(input int lane);
    act_addr = act_addr_flatten_o[(lane*ADDR_WIDTH)+:ADDR_WIDTH];
  endfunction

  function automatic logic [ADDR_WIDTH-1:0] weight_addr(input int lane, input int col);
    int idx;
    begin
      idx = (lane * SIZE) + col;
      weight_addr = weight_addr_flatten_o[(idx*ADDR_WIDTH)+:ADDR_WIDTH];
    end
  endfunction

  function automatic logic [DIM_WIDTH-1:0] k_index(input int lane);
    k_index = k_index_flatten_o[(lane*DIM_WIDTH)+:DIM_WIDTH];
  endfunction

  function automatic logic [DIM_WIDTH-1:0] oc_index(input int col);
    oc_index = oc_index_flatten_o[(col*DIM_WIDTH)+:DIM_WIDTH];
  endfunction

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

  task automatic expect_u16(input string label, input logic [15:0] actual, input logic [15:0] expected);
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, actual, expected);
    end
  endtask

  task automatic set_conv1_defaults();
    layer_type_i = LAYER_CONV;
    activation_base_addr_i = 16'd100;
    weight_base_addr_i = CONV1_WEIGHT_BASE;
    in_h_i = CONV1_IN_H;
    in_w_i = CONV1_IN_W;
    out_w_i = CONV1_OUT_W;
    out_ch_i = CONV1_OUT_CH;
    kernel_h_i = CONV1_KERNEL_H;
    kernel_w_i = CONV1_KERNEL_W;
    k_total_i = CONV1_K_TOTAL;
    spatial_idx_i = '0;
    k_tile_idx_i = '0;
    oc_tile_idx_i = '0;
  endtask

  task automatic set_fc2_defaults();
    layer_type_i = LAYER_FC;
    activation_base_addr_i = 16'd200;
    weight_base_addr_i = FC2_WEIGHT_BASE;
    in_h_i = FC2_IN_H;
    in_w_i = FC2_IN_W;
    out_w_i = FC2_OUT_W;
    out_ch_i = FC2_OUT_CH;
    kernel_h_i = FC2_KERNEL_H;
    kernel_w_i = FC2_KERNEL_W;
    k_total_i = FC2_K_TOTAL;
    spatial_idx_i = '0;
    k_tile_idx_i = '0;
    oc_tile_idx_i = '0;
  endtask

  task automatic check_conv_first_pixel();
    print_header("TEST: Conv address generation first K tile");
    set_conv1_defaults();
    spatial_idx_i = 16'd0;
    k_tile_idx_i = 16'd0;
    oc_tile_idx_i = 16'd0;
    #1;

    $display("  act_addr={lane1:%0d,lane0:%0d} weight_valid=%b weight_zero=%b",
             act_addr(1), act_addr(0), weight_valid_o, weight_zero_o);
    expect_u16("conv lane0 act addr", act_addr(0), 16'd100);
    expect_u16("conv lane1 act addr", act_addr(1), 16'd101);
    expect_flag("conv act valid asserted", act_valid_o == 2'b11);
    expect_flag("conv no padded activation", act_zero_o == 2'b00);
    expect_u16("conv k lane0", k_index(0), 16'd0);
    expect_u16("conv k lane1", k_index(1), 16'd1);
    expect_u16("conv oc col0", oc_index(0), 16'd0);
    expect_u16("conv oc col1", oc_index(1), 16'd1);
    expect_u16("conv w k0 oc0", weight_addr(0, 0), 16'd0);
    expect_u16("conv w k0 oc1", weight_addr(0, 1), 16'd9);
    expect_u16("conv w k1 oc0", weight_addr(1, 0), 16'd1);
    expect_u16("conv w k1 oc1", weight_addr(1, 1), 16'd10);
    expect_flag("conv all weights valid", weight_valid_o == 4'b1111);
    expect_flag("conv no zero weights", weight_zero_o == 4'b0000);
  endtask

  task automatic check_conv_k_tail();
    print_header("TEST: Conv padded K tail");
    set_conv1_defaults();
    spatial_idx_i = 16'd28;  // oh=1, ow=2 for out_w=26
    k_tile_idx_i = 16'd4;    // k={8,9}; k=9 is padded
    oc_tile_idx_i = 16'd3;   // oc={6,7}
    #1;

    $display("  act_addr={lane1:%0d,lane0:%0d} k={lane1:%0d,lane0:%0d} weight_valid=%b",
             act_addr(1), act_addr(0), k_index(1), k_index(0), weight_valid_o);
    expect_u16("conv tail lane0 act addr", act_addr(0), 16'd188);
    expect_u16("conv tail lane1 padded addr", act_addr(1), 16'd0);
    expect_flag("conv tail act valid still asserted", act_valid_o == 2'b11);
    expect_flag("conv tail lane1 zero", act_zero_o == 2'b10);
    expect_u16("conv tail k lane0", k_index(0), 16'd8);
    expect_u16("conv tail k lane1", k_index(1), 16'd9);
    expect_u16("conv tail oc col0", oc_index(0), 16'd6);
    expect_u16("conv tail oc col1", oc_index(1), 16'd7);
    expect_u16("conv tail w k8 oc6", weight_addr(0, 0), 16'd62);
    expect_u16("conv tail w k8 oc7", weight_addr(0, 1), 16'd71);
    expect_u16("conv tail padded w lane1 col0", weight_addr(1, 0), 16'd0);
    expect_u16("conv tail padded w lane1 col1", weight_addr(1, 1), 16'd0);
    expect_flag("conv tail weight valid mask", weight_valid_o == 4'b0011);
    expect_flag("conv tail weight zero mask", weight_zero_o == 4'b1100);
  endtask

  task automatic check_fc2_final_tile();
    print_header("TEST: FC address generation final valid tile");
    set_fc2_defaults();
    k_tile_idx_i = 16'd7;   // k={14,15}
    oc_tile_idx_i = 16'd4;  // oc={8,9}
    #1;

    $display("  act_addr={lane1:%0d,lane0:%0d} weight_addr={l1c1:%0d,l1c0:%0d,l0c1:%0d,l0c0:%0d}",
             act_addr(1), act_addr(0), weight_addr(1, 1), weight_addr(1, 0),
             weight_addr(0, 1), weight_addr(0, 0));
    expect_u16("fc2 lane0 act addr", act_addr(0), 16'd214);
    expect_u16("fc2 lane1 act addr", act_addr(1), 16'd215);
    expect_flag("fc2 no padded activation", act_zero_o == 2'b00);
    expect_u16("fc2 k lane0", k_index(0), 16'd14);
    expect_u16("fc2 k lane1", k_index(1), 16'd15);
    expect_u16("fc2 oc col0", oc_index(0), 16'd8);
    expect_u16("fc2 oc col1", oc_index(1), 16'd9);
    expect_u16("fc2 w k14 oc8", weight_addr(0, 0), 16'd4940);
    expect_u16("fc2 w k14 oc9", weight_addr(0, 1), 16'd4941);
    expect_u16("fc2 w k15 oc8", weight_addr(1, 0), 16'd4950);
    expect_u16("fc2 w k15 oc9", weight_addr(1, 1), 16'd4951);
    expect_flag("fc2 all weights valid", weight_valid_o == 4'b1111);
  endtask

  task automatic check_fc_padded_k();
    print_header("TEST: FC padded K lanes");
    set_fc2_defaults();
    k_tile_idx_i = 16'd8;   // k={16,17}; both padded for FC2
    oc_tile_idx_i = 16'd0;
    #1;

    $display("  act_zero=%b weight_valid=%b k={lane1:%0d,lane0:%0d}",
             act_zero_o, weight_valid_o, k_index(1), k_index(0));
    expect_flag("fc padded act valid asserted", act_valid_o == 2'b11);
    expect_flag("fc padded act zero mask", act_zero_o == 2'b11);
    expect_u16("fc padded lane0 addr", act_addr(0), 16'd0);
    expect_u16("fc padded lane1 addr", act_addr(1), 16'd0);
    expect_u16("fc padded k lane0", k_index(0), 16'd16);
    expect_u16("fc padded k lane1", k_index(1), 16'd17);
    expect_flag("fc padded no weights valid", weight_valid_o == 4'b0000);
    expect_flag("fc padded all weights zero", weight_zero_o == 4'b1111);
  endtask

  task automatic check_synthetic_tail_oc();
    print_header("TEST: Synthetic FC tail output-channel mask");
    set_fc2_defaults();
    weight_base_addr_i = 16'd1000;
    out_ch_i = 16'd9;
    k_tile_idx_i = 16'd7;   // k={14,15}
    oc_tile_idx_i = 16'd4;  // oc={8,9}; oc=9 is padded
    #1;

    $display("  oc={col1:%0d,col0:%0d} weight_valid=%b weight_zero=%b",
             oc_index(1), oc_index(0), weight_valid_o, weight_zero_o);
    expect_u16("tail oc col0", oc_index(0), 16'd8);
    expect_u16("tail oc col1", oc_index(1), 16'd9);
    expect_u16("tail oc w k14 oc8", weight_addr(0, 0), 16'd1134);
    expect_u16("tail oc padded w k14 oc9", weight_addr(0, 1), 16'd0);
    expect_u16("tail oc w k15 oc8", weight_addr(1, 0), 16'd1143);
    expect_u16("tail oc padded w k15 oc9", weight_addr(1, 1), 16'd0);
    expect_flag("tail oc weight valid mask", weight_valid_o == 4'b0101);
    expect_flag("tail oc weight zero mask", weight_zero_o == 4'b1010);
  endtask

  initial begin
    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    check_conv_first_pixel();
    check_conv_k_tail();
    check_fc2_final_tile();
    check_fc_padded_k();
    check_synthetic_tail_oc();

    $display("test_conv_fc_address_generator: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_conv_fc_address_generator failed");
    end
    $finish;
  end

endmodule : test_conv_fc_address_generator
