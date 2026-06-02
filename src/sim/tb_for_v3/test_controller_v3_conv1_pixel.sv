`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

module test_controller_v3_conv1_pixel;
  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int ACC_WIDTH = 32;
  localparam int ACC_DEPTH = 4;
  localparam int ACC_ADDR_WIDTH = $clog2(ACC_DEPTH);
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int REQUANT_MULT_WIDTH = 32;
  localparam int REQUANT_SHIFT_WIDTH = 6;
  localparam int MAX_NUM_TILES = 128;
  localparam int TILE_COUNT_WIDTH = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1;
  localparam int UB_BANK_DEPTH = 8192;
  localparam int UB_ADDR_WIDTH = $clog2(UB_BANK_DEPTH);
  localparam int WGT_ADDR_WIDTH = 13;
  localparam int WEIGHT_DEPTH = 4952;
  localparam int PARAM_DEPTH = 44;
  localparam int PARAM_ADDR_WIDTH = $clog2(PARAM_DEPTH);
  localparam int CLK_PERIOD = 10;
  localparam int TIMEOUT_CYCLES = 5000;

  localparam int POOL_BYPASS = 0;
  localparam int INPUT_COUNT = 784;
  localparam int CONV1_NUM_SPATIAL = 676;
  localparam int CONV1_OUT_CH = 8;
  localparam int CONV1_OUT_COUNT = CONV1_NUM_SPATIAL * CONV1_OUT_CH;
  localparam logic [15:0] CONV1_SPATIAL = 16'd161;
  localparam logic [UB_ADDR_WIDTH-1:0] ACT_BASE = '0;
  localparam logic [UB_ADDR_WIDTH-1:0] OUT_BASE = UB_ADDR_WIDTH'(300);

  logic clk;
  logic rst_n;

  logic signed [DATA_WIDTH-1:0] input_image_mem[0:INPUT_COUNT-1];
  logic signed [DATA_WIDTH-1:0] conv1_out_mem[0:CONV1_OUT_COUNT-1];

  logic host_mode;
  logic host_rd_en;
  logic host_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] host_rd_addr;
  logic host_wr_en;
  logic host_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] host_wr_addr;
  logic signed [DATA_WIDTH-1:0] host_wr_data;

  logic ub_rd_en;
  logic ub_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] ub_rd_addr;
  logic signed [DATA_WIDTH-1:0] ub_rd_data;
  logic ub_rd_valid;
  logic ub_wr_en;
  logic ub_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] ub_wr_addr;
  logic signed [DATA_WIDTH-1:0] ub_wr_data;

  logic start_i;
  logic clear_i;
  logic controller_done_o;
  logic controller_busy_o;
  logic controller_error_o;
  logic [4:0] controller_state_o;
  logic [4:0] controller_tile_state_o;
  logic [15:0] controller_spatial_idx_o;
  logic [15:0] controller_oc_tile_o;
  logic [15:0] controller_k_tile_o;
  logic [31:0] controller_cycle_count_o;
  logic [31:0] controller_tile_count_o;
  logic [31:0] controller_error_code_o;

  logic ctrl_ub_rd_bank_w;
  logic ctrl_ub_wr_en_w;
  logic ctrl_ub_wr_bank_w;
  logic [UB_ADDR_WIDTH-1:0] ctrl_ub_wr_addr_w;
  logic signed [DATA_WIDTH-1:0] ctrl_ub_wr_data_w;

  logic wgt_req_valid_w;
  logic wgt_req_ready_w;
  logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0] wgt_req_addr_flatten_w;
  logic [SIZE*SIZE-1:0] wgt_req_valid_mask_w;
  logic [SIZE*SIZE-1:0] wgt_req_zero_mask_w;
  logic [15:0] wgt_req_tag_w;
  logic wgt_tile_release_w;
  logic wgt_stream_start_w;
  logic wgt_tile_valid_w;
  logic [SIZE-1:0] wgt_load_done_w;

  logic act_req_valid_w;
  logic act_req_ready_w;
  logic [SIZE*UB_ADDR_WIDTH-1:0] act_req_addr_flatten_w;
  logic [SIZE-1:0] act_req_lane_valid_w;
  logic [SIZE-1:0] act_req_lane_zero_w;
  logic [15:0] act_req_tag_w;
  logic act_launch_ready_w;
  logic act_launch_w;

  logic clear_dp_i;
  logic compute_enable_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_w;

  logic dp_ub_rd_en_w;
  logic [UB_ADDR_WIDTH-1:0] dp_ub_rd_addr_w;
  logic signed [DATA_WIDTH-1:0] dp_ub_rd_data_w;
  logic dp_ub_rd_valid_w;

  logic weight_rd_en_w;
  logic [WGT_ADDR_WIDTH-1:0] weight_rd_addr_w;
  logic signed [DATA_WIDTH-1:0] weight_rd_data_w;
  logic weight_rd_valid_w;

  logic accumulator_clear_all_w;
  logic accumulator_row_clear_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_w;
  logic accumulator_write_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_w;
  logic accumulator_read_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_w;

  logic vpu_input_done_w;
  logic [1:0] vpu_act_mode_w;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_w;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_w;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_w;
  logic signed [ACC_WIDTH-1:0] vpu_output_zero_point_w;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_w;
  logic [SIZE-1:0] mxu_psum_valid_w;
  logic psum_packer_busy_w;

  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_w;
  logic accumulator_read_valid_w;
  logic accumulator_row_done_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_done_addr_w;
  logic [ACC_DEPTH-1:0] accumulator_row_ready_w;

  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_w;
  logic vpu_data_valid_w;
  logic datapath_done_w;

  logic overflow_clr_w;
  logic [SIZE*SIZE-1:0] overflow_flatten_w;

  logic [31:0] dbg_act_fetch_cycles_w;
  logic [31:0] dbg_act_output_stall_cycles_w;
  logic [31:0] dbg_act_vectors_pushed_w;
  logic [31:0] dbg_act_lane_reads_w;
  logic [31:0] dbg_weight_load_cycles_w;
  logic [31:0] dbg_weight_reuse_count_w;
  logic [31:0] dbg_weight_buffer_empty_cycles_w;
  logic [31:0] dbg_weight_buffer_full_cycles_w;

  int test_count;
  int pass_count;
  int fail_count;
  int captured_acc_count;

  assign ub_rd_en   = host_mode ? host_rd_en   : dp_ub_rd_en_w;
  assign ub_rd_bank = host_mode ? host_rd_bank : ctrl_ub_rd_bank_w;
  assign ub_rd_addr = host_mode ? host_rd_addr : dp_ub_rd_addr_w;
  assign ub_wr_en   = host_mode ? host_wr_en   : ctrl_ub_wr_en_w;
  assign ub_wr_bank = host_mode ? host_wr_bank : ctrl_ub_wr_bank_w;
  assign ub_wr_addr = host_mode ? host_wr_addr : ctrl_ub_wr_addr_w;
  assign ub_wr_data = host_mode ? host_wr_data : ctrl_ub_wr_data_w;

  unified_buffer #(
      .DATA_WIDTH(DATA_WIDTH),
      .BANK_DEPTH(UB_BANK_DEPTH),
      .ADDR_WIDTH(UB_ADDR_WIDTH)
  ) u_unified_buffer (
      .clk       (clk),
      .rst_n     (rst_n),
      .rd_en_i   (ub_rd_en),
      .rd_bank_i (ub_rd_bank),
      .rd_addr_i (ub_rd_addr),
      .rd_data_o (ub_rd_data),
      .rd_valid_o(ub_rd_valid),
      .wr_en_i   (ub_wr_en),
      .wr_bank_i (ub_wr_bank),
      .wr_addr_i (ub_wr_addr),
      .wr_data_i (ub_wr_data)
  );

  weight_rom #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH     (WEIGHT_DEPTH),
      .ADDR_WIDTH(WGT_ADDR_WIDTH),
      .INIT_FILE ("../../rtl/v3/small_cnn_sym_weights_i8.mem")
  ) u_weight_rom (
      .clk    (clk),
      .rst_n  (rst_n),
      .en_i   (weight_rd_en_w),
      .addr_i (weight_rd_addr_w),
      .data_o (weight_rd_data_w),
      .valid_o(weight_rd_valid_w)
  );

  tpu_controller_v3_rom_layer #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .UB_ADDR_WIDTH      (UB_ADDR_WIDTH),
      .WGT_ADDR_WIDTH     (WGT_ADDR_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .PARAM_DEPTH        (PARAM_DEPTH),
      .PARAM_ADDR_WIDTH   (PARAM_ADDR_WIDTH),
      .BANK_DEPTH         (UB_BANK_DEPTH),
      .BIAS_INIT_FILE     ("../../rtl/v3/small_cnn_sym_biases_i32.mem"),
      .REQUANT_MULT_INIT_FILE("../../rtl/v3/small_cnn_sym_requant_mult_i32.mem"),
      .REQUANT_SHIFT_INIT_FILE("../../rtl/v3/small_cnn_sym_requant_shift_u6.mem")
  ) u_controller (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .start_i                          (start_i),
      .clear_i                          (clear_i),
      .done_o                           (controller_done_o),
      .busy_o                           (controller_busy_o),
      .error_o                          (controller_error_o),
      .dbg_state_o                      (controller_state_o),
      .dbg_tile_state_o                 (controller_tile_state_o),
      .dbg_spatial_idx_o                (controller_spatial_idx_o),
      .dbg_oc_tile_o                    (controller_oc_tile_o),
      .dbg_k_tile_o                     (controller_k_tile_o),
      .dbg_cycle_count_o                (controller_cycle_count_o),
      .dbg_tile_count_o                 (controller_tile_count_o),
      .dbg_error_code_o                 (controller_error_code_o),
      .layer_idx_i                      (LAYER_IDX_CONV1),
      .use_descriptor_banks_i           (1'b0),
      .read_bank_i                      (1'b0),
      .write_bank_i                     (1'b1),
      .activation_base_addr_i           (ACT_BASE),
      .output_base_addr_i               (OUT_BASE),
      .spatial_idx_i                    (CONV1_SPATIAL),
      .single_spatial_i                 (1'b1),
      .ub_rd_bank_o                     (ctrl_ub_rd_bank_w),
      .ub_wr_en_o                       (ctrl_ub_wr_en_w),
      .ub_wr_bank_o                     (ctrl_ub_wr_bank_w),
      .ub_wr_addr_o                     (ctrl_ub_wr_addr_w),
      .ub_wr_data_o                     (ctrl_ub_wr_data_w),
      .wgt_req_valid_o                  (wgt_req_valid_w),
      .wgt_req_ready_i                  (wgt_req_ready_w),
      .wgt_req_addr_flatten_o           (wgt_req_addr_flatten_w),
      .wgt_req_valid_mask_o             (wgt_req_valid_mask_w),
      .wgt_req_zero_mask_o              (wgt_req_zero_mask_w),
      .wgt_req_tag_o                    (wgt_req_tag_w),
      .wgt_tile_release_o               (wgt_tile_release_w),
      .wgt_stream_start_o               (wgt_stream_start_w),
      .wgt_tile_valid_i                 (wgt_tile_valid_w),
      .wgt_load_done_i                  (wgt_load_done_w),
      .act_req_valid_o                  (act_req_valid_w),
      .act_req_ready_i                  (act_req_ready_w),
      .act_req_addr_flatten_o           (act_req_addr_flatten_w),
      .act_req_lane_valid_o             (act_req_lane_valid_w),
      .act_req_lane_zero_o              (act_req_lane_zero_w),
      .act_req_tag_o                    (act_req_tag_w),
      .act_launch_ready_i               (act_launch_ready_w),
      .act_launch_o                     (act_launch_w),
      .accumulator_clear_all_o          (accumulator_clear_all_w),
      .accumulator_row_clear_o          (accumulator_row_clear_w),
      .accumulator_row_clear_addr_o     (accumulator_row_clear_addr_w),
      .accumulator_write_en_o           (accumulator_write_en_w),
      .accumulator_write_addr_o         (accumulator_write_addr_w),
      .accumulator_read_en_o            (accumulator_read_en_w),
      .accumulator_read_addr_o          (accumulator_read_addr_w),
      .accumulator_read_valid_i         (accumulator_read_valid_w),
      .accumulator_row_ready_i          (accumulator_row_ready_w),
      .vpu_input_done_o                 (vpu_input_done_w),
      .vpu_act_mode_o                   (vpu_act_mode_w),
      .vpu_bias_flatten_o               (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_o (vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_o      (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_o          (vpu_output_zero_point_w),
      .vpu_data_flatten_i               (vpu_data_flatten_w),
      .vpu_data_valid_i                 (vpu_data_valid_w),
      .mxu_psum_valid_i                 (mxu_psum_valid_w),
      .psum_packer_busy_i               (psum_packer_busy_w),
      .num_tiles_o                      (num_tiles_w)
  );

  tpu_datapath_v3 #(
      .SIZE                 (SIZE),
      .DATA_WIDTH           (DATA_WIDTH),
      .ACT_ADDR_WIDTH       (UB_ADDR_WIDTH),
      .WGT_ADDR_WIDTH       (WGT_ADDR_WIDTH),
      .LOCAL_PSUM_WIDTH     (LOCAL_PSUM_WIDTH),
      .MAX_NUM_TILES        (MAX_NUM_TILES),
      .ACC_WIDTH            (ACC_WIDTH),
      .ACC_DEPTH            (ACC_DEPTH),
      .ACC_ADDR_WIDTH       (ACC_ADDR_WIDTH),
      .ACT_WIDTH            (ACC_WIDTH),
      .OUT_WIDTH            (OUT_WIDTH),
      .QUANT_ENABLE         (1'b1),
      .BIAS_WIDTH           (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH   (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH  (REQUANT_SHIFT_WIDTH),
      .NORM_SHIFT           (0),
      .NORM_ROUND_ENABLE    (1'b1),
      .POOL_MODE            (POOL_BYPASS),
      .POOL_WINDOW          (2),
      .GATED_ACT_LAUNCH     (1'b1),
      .TILE_COUNT_WIDTH     (TILE_COUNT_WIDTH)
  ) u_datapath (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .clear_i                          (clear_dp_i),
      .compute_enable_i                 (compute_enable_i),
      .num_tiles_i                      (num_tiles_w),
      .act_req_valid_i                  (act_req_valid_w),
      .act_req_ready_o                  (act_req_ready_w),
      .act_req_addr_flatten_i           (act_req_addr_flatten_w),
      .act_req_lane_valid_i             (act_req_lane_valid_w),
      .act_req_lane_zero_i              (act_req_lane_zero_w),
      .act_req_tag_i                    (act_req_tag_w),
      .act_launch_i                     (act_launch_w),
      .act_launch_ready_o               (act_launch_ready_w),
      .ub_rd_en_o                       (dp_ub_rd_en_w),
      .ub_rd_addr_o                     (dp_ub_rd_addr_w),
      .ub_rd_data_i                     (dp_ub_rd_data_w),
      .ub_rd_valid_i                    (dp_ub_rd_valid_w),
      .wgt_req_valid_i                  (wgt_req_valid_w),
      .wgt_req_ready_o                  (wgt_req_ready_w),
      .wgt_req_addr_flatten_i           (wgt_req_addr_flatten_w),
      .wgt_req_valid_mask_i             (wgt_req_valid_mask_w),
      .wgt_req_zero_mask_i              (wgt_req_zero_mask_w),
      .wgt_req_tag_i                    (wgt_req_tag_w),
      .wgt_tile_release_i               (wgt_tile_release_w),
      .wgt_stream_start_i               (wgt_stream_start_w),
      .wgt_stream_ready_o               (),
      .wgt_tile_valid_o                 (wgt_tile_valid_w),
      .wgt_tile_tag_o                   (),
      .wgt_stream_done_o                (),
      .weight_rd_en_o                   (weight_rd_en_w),
      .weight_rd_addr_o                 (weight_rd_addr_w),
      .weight_rd_data_i                 (weight_rd_data_w),
      .weight_rd_valid_i                (weight_rd_valid_w),
      .accumulator_clear_all_i          (accumulator_clear_all_w),
      .accumulator_row_clear_i          (accumulator_row_clear_w),
      .accumulator_row_clear_addr_i     (accumulator_row_clear_addr_w),
      .accumulator_write_en_i           (accumulator_write_en_w),
      .accumulator_write_addr_i         (accumulator_write_addr_w),
      .accumulator_read_en_i            (accumulator_read_en_w),
      .accumulator_read_addr_i          (accumulator_read_addr_w),
      .vpu_input_done_i                 (vpu_input_done_w),
      .vpu_act_mode_i                   (vpu_act_mode_w),
      .vpu_bias_flatten_i               (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_i (vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_i      (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_i          (vpu_output_zero_point_w),
      .mxu_psum_flatten_o               (mxu_psum_flatten_w),
      .mxu_psum_valid_o                 (mxu_psum_valid_w),
      .mxu_valid_mac_count_o            (),
      .psum_packer_busy_o               (psum_packer_busy_w),
      .wgt_load_done_o                  (wgt_load_done_w),
      .accumulator_read_flatten_o       (accumulator_read_flatten_w),
      .accumulator_read_valid_o         (accumulator_read_valid_w),
      .accumulator_row_done_o           (accumulator_row_done_w),
      .accumulator_row_done_addr_o      (accumulator_row_done_addr_w),
      .accumulator_row_ready_o          (accumulator_row_ready_w),
      .vpu_data_flatten_o               (vpu_data_flatten_w),
      .vpu_data_valid_o                 (vpu_data_valid_w),
      .done_o                           (datapath_done_w),
      .overflow_clr_i                   (overflow_clr_w),
      .overflow_flatten_o               (overflow_flatten_w),
      .dbg_act_fetch_cycles_o           (dbg_act_fetch_cycles_w),
      .dbg_act_output_stall_cycles_o    (dbg_act_output_stall_cycles_w),
      .dbg_act_vectors_pushed_o         (dbg_act_vectors_pushed_w),
      .dbg_act_lane_reads_o             (dbg_act_lane_reads_w),
      .dbg_weight_load_cycles_o         (dbg_weight_load_cycles_w),
      .dbg_weight_reuse_count_o         (dbg_weight_reuse_count_w),
      .dbg_weight_buffer_empty_cycles_o (dbg_weight_buffer_empty_cycles_w),
      .dbg_weight_buffer_full_cycles_o  (dbg_weight_buffer_full_cycles_w)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  assign dp_ub_rd_data_w = ub_rd_data;
  assign dp_ub_rd_valid_w = ub_rd_valid && !host_mode;

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

  task automatic expect_i8_eq(
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

  task automatic expect_i32_eq(
      input string label,
      input logic signed [ACC_WIDTH-1:0] actual,
      input logic signed [ACC_WIDTH-1:0] expected
  );
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic init_signals();
    rst_n = 1'b0;
    host_mode = 1'b1;
    host_rd_en = 1'b0;
    host_rd_bank = 1'b0;
    host_rd_addr = '0;
    host_wr_en = 1'b0;
    host_wr_bank = 1'b0;
    host_wr_addr = '0;
    host_wr_data = '0;
    start_i = 1'b0;
    clear_i = 1'b0;
    clear_dp_i = 1'b0;
    compute_enable_i = 1'b1;
    overflow_clr_w = 1'b0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    captured_acc_count = 0;
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
  endtask

  task automatic host_write(
      input logic bank,
      input logic [UB_ADDR_WIDTH-1:0] addr,
      input logic signed [DATA_WIDTH-1:0] data
  );
    @(negedge clk);
    host_wr_bank = bank;
    host_wr_addr = addr;
    host_wr_data = data;
    host_wr_en = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    host_wr_en = 1'b0;
  endtask

  task automatic host_read(
      input logic bank,
      input logic [UB_ADDR_WIDTH-1:0] addr,
      output logic signed [DATA_WIDTH-1:0] data
  );
    @(negedge clk);
    host_rd_bank = bank;
    host_rd_addr = addr;
    host_rd_en = 1'b1;
    @(posedge clk);
    #1;
    data = ub_rd_data;
    @(negedge clk);
    host_rd_en = 1'b0;
  endtask

  task automatic preload_input_image();
    print_header("TEST: Host preload input image");
    host_mode = 1'b1;
    $readmemh("../../../CNN_model/python/mnist_classification/18_05/input_image_i8.hex",
              input_image_mem);
    $readmemh("../../../CNN_model/python/mnist_classification/18_05/layer0_out_i8.hex",
              conv1_out_mem);

    for (int idx = 0; idx < INPUT_COUNT; idx++) begin
      host_write(1'b0, UB_ADDR_WIDTH'(idx), input_image_mem[idx]);
    end

    $display("  UB bank0[0:%0d] loaded from input_image_i8.hex", INPUT_COUNT - 1);
    $display("  Conv1 single pixel: spatial=%0d expected acc oc0/1={lane1:19653,lane0:9485}",
             CONV1_SPATIAL);
  endtask

  task automatic run_conv1_pixel();
    int cycles;

    print_header("TEST: V3 ROM layer controller -> Conv1 single pixel");
    host_mode = 1'b0;

    @(negedge clk);
    start_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    start_i = 1'b0;

    cycles = 0;
    while (!controller_done_o && !controller_error_o && (cycles < TIMEOUT_CYCLES)) begin
      @(posedge clk);
      #1;
      cycles++;

      if (vpu_data_valid_w) begin
        $display("  VPU OUT : oc_tile=%0d data={lane1:%0d,lane0:%0d}",
                 controller_oc_tile_o,
                 $signed(vpu_data_flatten_w[(1*OUT_WIDTH)+:OUT_WIDTH]),
                 $signed(vpu_data_flatten_w[(0*OUT_WIDTH)+:OUT_WIDTH]));
      end

      if (accumulator_read_valid_w) begin
        captured_acc_count++;
        $display("  ACC READ: oc_tile=%0d data={lane1:%0d,lane0:%0d}",
                 controller_oc_tile_o,
                 $signed(accumulator_read_flatten_w[(1*ACC_WIDTH)+:ACC_WIDTH]),
                 $signed(accumulator_read_flatten_w[(0*ACC_WIDTH)+:ACC_WIDTH]));

        if (controller_oc_tile_o == 16'd0) begin
          expect_i32_eq("conv1 acc oc0",
                        accumulator_read_flatten_w[(0*ACC_WIDTH)+:ACC_WIDTH],
                        32'sd9485);
          expect_i32_eq("conv1 acc oc1",
                        accumulator_read_flatten_w[(1*ACC_WIDTH)+:ACC_WIDTH],
                        32'sd19653);
        end
      end
    end

    $display("  CTRL   : done=%b error=%b state=%0d tile_state=%0d spatial=%0d oc_tile=%0d k_tile=%0d cycles=%0d tiles=%0d err=0x%08h",
             controller_done_o, controller_error_o, controller_state_o, controller_tile_state_o,
             controller_spatial_idx_o, controller_oc_tile_o, controller_k_tile_o,
             controller_cycle_count_o, controller_tile_count_o, controller_error_code_o);

    expect_flag("controller finished", controller_done_o);
    expect_flag("controller no error", !controller_error_o);
    expect_flag("datapath no overflow", overflow_flatten_w == '0);
    expect_flag("all Conv1 oc tiles completed", controller_tile_count_o == 32'd4);
    expect_flag("all Conv1 accumulator reads observed", captured_acc_count == 4);
  endtask

  task automatic check_output_buffer();
    logic signed [DATA_WIDTH-1:0] actual;
    logic signed [DATA_WIDTH-1:0] expected;
    logic [UB_ADDR_WIDTH-1:0] addr;
    int mismatches;

    print_header("TEST: Host readback Conv1 single pixel outputs");
    host_mode = 1'b1;
    mismatches = 0;

    $write("  outputs = {");
    for (int oc = 0; oc < CONV1_OUT_CH; oc++) begin
      addr = OUT_BASE + UB_ADDR_WIDTH'(oc * CONV1_NUM_SPATIAL) + UB_ADDR_WIDTH'(CONV1_SPATIAL);
      expected = conv1_out_mem[(oc * CONV1_NUM_SPATIAL) + int'(CONV1_SPATIAL)];
      host_read(1'b1, addr, actual);
      if (oc != 0) begin
        $write(",");
      end
      $write("%0d", $signed(actual));
      expect_i8_eq($sformatf("conv1 out oc%0d", oc), actual, expected);
      if (actual !== expected) begin
        mismatches++;
      end
    end
    $display("}");
    $display("  expected oc0=%0d oc1=%0d mismatches=%0d",
             $signed(conv1_out_mem[CONV1_SPATIAL]),
             $signed(conv1_out_mem[CONV1_NUM_SPATIAL + int'(CONV1_SPATIAL)]),
             mismatches);
  endtask

  initial begin
    init_signals();
    reset_dut();

    preload_input_image();
    run_conv1_pixel();
    check_output_buffer();

    $display("");
    $display("DEBUG COUNTERS");
    $display("  ctrl_cycles=%0d final_state=%0d final_spatial=%0d final_oc_tile=%0d final_k_tile=%0d tiles=%0d",
             controller_cycle_count_o, controller_state_o, controller_spatial_idx_o,
             controller_oc_tile_o, controller_k_tile_o, controller_tile_count_o);
    $display("  act_fetch=%0d act_vectors=%0d act_lane_reads=%0d",
             dbg_act_fetch_cycles_w, dbg_act_vectors_pushed_w, dbg_act_lane_reads_w);
    $display("  wgt_load=%0d wgt_reuse=%0d wgt_empty=%0d wgt_full=%0d",
             dbg_weight_load_cycles_w, dbg_weight_reuse_count_w,
             dbg_weight_buffer_empty_cycles_w, dbg_weight_buffer_full_cycles_w);

    $display("test_controller_v3_conv1_pixel: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_controller_v3_conv1_pixel failed");
    end
    $finish;
  end

endmodule : test_controller_v3_conv1_pixel
