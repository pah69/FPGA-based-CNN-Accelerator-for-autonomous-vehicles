`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

`ifndef TPU_SIZE
`define TPU_SIZE 2
`endif

module test_controller_rom_tile;

  localparam int SIZE = `TPU_SIZE;
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
  localparam int TILE_COUNT_WIDTH = $clog2(MAX_NUM_TILES + 1);
  localparam int UB_BANK_DEPTH = 512;
  localparam int UB_ADDR_WIDTH = $clog2(UB_BANK_DEPTH);
  localparam int WGT_FIFO_DEPTH = 8;
  localparam int CLK_PERIOD = 10;
  localparam int TIMEOUT_CYCLES = 400;
  localparam int ACC_COUNT_WIDTH = ACC_ADDR_WIDTH + 1;

  localparam int POOL_BYPASS = 0;
  localparam logic [UB_ADDR_WIDTH-1:0] ACT_BASE = UB_ADDR_WIDTH'(200);
  localparam logic [UB_ADDR_WIDTH-1:0] OUT_BASE = UB_ADDR_WIDTH'(10);
  localparam logic [UB_ADDR_WIDTH-1:0] FC2_ACT0_ADDR = UB_ADDR_WIDTH'(214);
  localparam logic [UB_ADDR_WIDTH-1:0] FC2_ACT1_ADDR = UB_ADDR_WIDTH'(215);
  localparam logic [UB_ADDR_WIDTH-1:0] FC2_OUT0_ADDR = UB_ADDR_WIDTH'(18);
  localparam logic [UB_ADDR_WIDTH-1:0] FC2_OUT1_ADDR = UB_ADDR_WIDTH'(19);

  logic clk;
  logic rst_n;

  logic host_mode;
  logic host_rd_en;
  logic host_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] host_rd_addr;
  logic host_wr_en;
  logic host_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] host_wr_addr;
  logic signed [DATA_WIDTH-1:0] host_wr_data;

  logic ctrl_rd_en;
  logic ctrl_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] ctrl_rd_addr;
  logic ctrl_wr_en;
  logic ctrl_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] ctrl_wr_addr;
  logic signed [DATA_WIDTH-1:0] ctrl_wr_data;

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
  logic controller_done_o;
  logic controller_busy_o;
  logic controller_error_o;
  logic [4:0] controller_state_o;
  logic [4:0] controller_inner_state_o;
  logic [15:0] controller_cycle_count_o;
  logic [31:0] controller_error_code_o;

  logic use_descriptor_banks_i;
  logic read_bank_i;
  logic write_bank_i;
  logic [UB_ADDR_WIDTH-1:0] activation_base_addr_i;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_i;
  logic [ACC_ADDR_WIDTH:0] block_size_i;
  logic [15:0] spatial_idx_i;
  logic [15:0] k_tile_idx_i;
  logic [15:0] oc_tile_idx_i;

  logic work_w;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_w;
  logic start_wgt_load_w;
  logic [(DATA_WIDTH*SIZE)-1:0] wgt_fifo_wdata_w;
  logic wgt_fifo_wr_en_w;
  logic wgt_fifo_full_w;
  logic wgt_fifo_empty_w;
  logic wgt_fetcher_ready_w;
  logic [SIZE-1:0] wgt_load_done_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_w;
  logic [SIZE-1:0] act_valid_raw_w;

  logic accumulator_clear_all_w;
  logic accumulator_row_clear_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_w;
  logic accumulator_write_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_w;
  logic accumulator_read_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_w;
  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_w;
  logic accumulator_read_valid_w;
  logic accumulator_row_done_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_done_addr_w;
  logic [ACC_DEPTH-1:0] accumulator_row_ready_w;

  logic vpu_input_done_w;
  logic [1:0] vpu_act_mode_w;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_w;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_w;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_w;
  logic signed [ACC_WIDTH-1:0] vpu_output_zero_point_w;
  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_w;
  logic vpu_data_valid_w;
  logic datapath_done_w;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_w;
  logic [SIZE-1:0] mxu_psum_valid_w;
  logic psum_packer_busy_w;
  logic overflow_clr_w;
  logic [SIZE*SIZE-1:0] overflow_flatten_w;

  int test_count;
  int pass_count;
  int fail_count;

  assign ub_rd_en   = host_mode ? host_rd_en   : ctrl_rd_en;
  assign ub_rd_bank = host_mode ? host_rd_bank : ctrl_rd_bank;
  assign ub_rd_addr = host_mode ? host_rd_addr : ctrl_rd_addr;
  assign ub_wr_en   = host_mode ? host_wr_en   : ctrl_wr_en;
  assign ub_wr_bank = host_mode ? host_wr_bank : ctrl_wr_bank;
  assign ub_wr_addr = host_mode ? host_wr_addr : ctrl_wr_addr;
  assign ub_wr_data = host_mode ? host_wr_data : ctrl_wr_data;

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

  tpu_controller_rom_tile #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .UB_ADDR_WIDTH      (UB_ADDR_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .BANK_DEPTH         (UB_BANK_DEPTH)
  ) u_controller (
      .clk                             (clk),
      .rst_n                           (rst_n),
      .start_i                         (start_i),
      .done_o                          (controller_done_o),
      .busy_o                          (controller_busy_o),
      .error_o                         (controller_error_o),
      .dbg_state_o                     (controller_state_o),
      .dbg_inner_state_o               (controller_inner_state_o),
      .dbg_cycle_count_o               (controller_cycle_count_o),
      .dbg_error_code_o                (controller_error_code_o),
      .layer_idx_i                     (LAYER_IDX_FC2),
      .use_descriptor_banks_i          (use_descriptor_banks_i),
      .read_bank_i                     (read_bank_i),
      .write_bank_i                    (write_bank_i),
      .activation_base_addr_i          (activation_base_addr_i),
      .output_base_addr_i              (output_base_addr_i),
      .block_size_i                    (block_size_i),
      .spatial_idx_i                   (spatial_idx_i),
      .k_tile_idx_i                    (k_tile_idx_i),
      .oc_tile_idx_i                   (oc_tile_idx_i),
      .ub_rd_en_o                      (ctrl_rd_en),
      .ub_rd_bank_o                    (ctrl_rd_bank),
      .ub_rd_addr_o                    (ctrl_rd_addr),
      .ub_rd_data_i                    (ub_rd_data),
      .ub_rd_valid_i                   (ub_rd_valid),
      .ub_wr_en_o                      (ctrl_wr_en),
      .ub_wr_bank_o                    (ctrl_wr_bank),
      .ub_wr_addr_o                    (ctrl_wr_addr),
      .ub_wr_data_o                    (ctrl_wr_data),
      .work_o                          (work_w),
      .num_tiles_o                     (num_tiles_w),
      .start_wgt_load_o                (start_wgt_load_w),
      .wgt_fifo_wdata_o                (wgt_fifo_wdata_w),
      .wgt_fifo_wr_en_o                (wgt_fifo_wr_en_w),
      .wgt_fifo_full_i                 (wgt_fifo_full_w),
      .wgt_fetcher_ready_i             (wgt_fetcher_ready_w),
      .wgt_load_done_i                 (wgt_load_done_w),
      .act_flat_raw_o                  (act_flat_raw_w),
      .act_valid_raw_o                 (act_valid_raw_w),
      .accumulator_clear_all_o         (accumulator_clear_all_w),
      .accumulator_row_clear_o         (accumulator_row_clear_w),
      .accumulator_row_clear_addr_o    (accumulator_row_clear_addr_w),
      .accumulator_write_en_o          (accumulator_write_en_w),
      .accumulator_write_addr_o        (accumulator_write_addr_w),
      .accumulator_read_en_o           (accumulator_read_en_w),
      .accumulator_read_addr_o         (accumulator_read_addr_w),
      .accumulator_row_ready_i         (accumulator_row_ready_w),
      .vpu_input_done_o                (vpu_input_done_w),
      .vpu_act_mode_o                  (vpu_act_mode_w),
      .vpu_bias_flatten_o              (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_o(vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_o     (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_o         (vpu_output_zero_point_w),
      .vpu_data_flatten_i              (vpu_data_flatten_w),
      .vpu_data_valid_i                (vpu_data_valid_w),
      .mxu_psum_valid_i                (mxu_psum_valid_w),
      .psum_packer_busy_i              (psum_packer_busy_w)
  );

  tpu_datapath_v2 #(
      .SIZE                 (SIZE),
      .DATA_WIDTH           (DATA_WIDTH),
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
      .WGT_FIFO_DEPTH       (WGT_FIFO_DEPTH),
      .TILE_COUNT_WIDTH     (TILE_COUNT_WIDTH)
  ) u_datapath (
      .clk                             (clk),
      .rst_n                           (rst_n),
      .work_i                          (work_w),
      .num_tiles_i                     (num_tiles_w),
      .start_wgt_load_i                (start_wgt_load_w),
      .wgt_fetcher_ready_o             (wgt_fetcher_ready_w),
      .wgt_fifo_wdata_i                (wgt_fifo_wdata_w),
      .wgt_fifo_wr_en_i                (wgt_fifo_wr_en_w),
      .wgt_fifo_full_o                 (wgt_fifo_full_w),
      .wgt_fifo_empty_o                (wgt_fifo_empty_w),
      .act_flat_raw_i                  (act_flat_raw_w),
      .act_valid_raw_i                 (act_valid_raw_w),
      .accumulator_clear_all_i         (accumulator_clear_all_w),
      .accumulator_row_clear_i         (accumulator_row_clear_w),
      .accumulator_row_clear_addr_i    (accumulator_row_clear_addr_w),
      .accumulator_write_en_i          (accumulator_write_en_w),
      .accumulator_write_addr_i        (accumulator_write_addr_w),
      .accumulator_read_en_i           (accumulator_read_en_w),
      .accumulator_read_addr_i         (accumulator_read_addr_w),
      .vpu_input_done_i                (vpu_input_done_w),
      .vpu_act_mode_i                  (vpu_act_mode_w),
      .vpu_bias_flatten_i              (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_i(vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_i     (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_i         (vpu_output_zero_point_w),
      .mxu_psum_flatten_o              (mxu_psum_flatten_w),
      .mxu_psum_valid_o                (mxu_psum_valid_w),
      .psum_packer_busy_o              (psum_packer_busy_w),
      .wgt_load_done_o                 (wgt_load_done_w),
      .accumulator_read_flatten_o      (accumulator_read_flatten_w),
      .accumulator_read_valid_o        (accumulator_read_valid_w),
      .accumulator_row_done_o          (accumulator_row_done_w),
      .accumulator_row_done_addr_o     (accumulator_row_done_addr_w),
      .accumulator_row_ready_o         (accumulator_row_ready_w),
      .vpu_data_flatten_o              (vpu_data_flatten_w),
      .vpu_data_valid_o                (vpu_data_valid_w),
      .done_o                          (datapath_done_w),
      .overflow_clr_i                  (overflow_clr_w),
      .overflow_flatten_o              (overflow_flatten_w)
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
    use_descriptor_banks_i = 1'b0;
    read_bank_i = 1'b0;
    write_bank_i = 1'b1;
    activation_base_addr_i = ACT_BASE;
    output_base_addr_i = OUT_BASE;
    block_size_i = ACC_COUNT_WIDTH'(1);
    spatial_idx_i = 16'd0;
    k_tile_idx_i = 16'd7;
    oc_tile_idx_i = 16'(8 / SIZE);
    overflow_clr_w = 1'b0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
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

  task automatic preload_fc2_vector();
    print_header("TEST: Host preload FC2 activation tile");
    host_mode = 1'b1;
    host_write(1'b0, FC2_ACT0_ADDR, 8'sd4);
    host_write(1'b0, FC2_ACT1_ADDR, 8'sd6);
    $display("  UB bank0[%0d:%0d] = {%0d,%0d}", FC2_ACT0_ADDR, FC2_ACT1_ADDR, 4, 6);
    $display("  FC2 tile: k_tile=%0d oc_tile=%0d uses ROM weights {4940,4941,4950,4951}",
             k_tile_idx_i, oc_tile_idx_i);
  endtask

  task automatic run_rom_controller_datapath();
    int cycles;

    print_header("TEST: ROM controller -> UB -> TPU datapath");
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

      if (mxu_psum_valid_w[0]) begin
        $display("  CAPTURE: MXU psum lane0 = %0d",
                 $signed(mxu_psum_flatten_w[(0*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH]));
      end
      if (mxu_psum_valid_w[1]) begin
        $display("  CAPTURE: MXU psum lane1 = %0d",
                 $signed(mxu_psum_flatten_w[(1*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH]));
      end
      if (accumulator_row_done_w) begin
        $display("  ACC DONE: row=%0d ready=%b", accumulator_row_done_addr_w,
                 accumulator_row_ready_w[accumulator_row_done_addr_w]);
      end
      if (vpu_data_valid_w) begin
        $display("  VPU OUT : data={lane1:%0d,lane0:%0d}",
                 $signed(vpu_data_flatten_w[(1*OUT_WIDTH)+:OUT_WIDTH]),
                 $signed(vpu_data_flatten_w[(0*OUT_WIDTH)+:OUT_WIDTH]));
      end
    end

    $display("  CTRL   : done=%b error=%b state=%0d inner=%0d cycles=%0d err=0x%08h",
             controller_done_o, controller_error_o, controller_state_o,
             controller_inner_state_o, controller_cycle_count_o, controller_error_code_o);

    expect_flag("controller finished", controller_done_o);
    expect_flag("controller no error", !controller_error_o);
    expect_flag("datapath no overflow", overflow_flatten_w == '0);
  endtask

  task automatic check_output_buffer();
    logic signed [DATA_WIDTH-1:0] lane0;
    logic signed [DATA_WIDTH-1:0] lane1;

    print_header("TEST: Host readback ROM-driven FC2 tile");
    host_mode = 1'b1;
    host_read(1'b1, FC2_OUT0_ADDR, lane0);
    host_read(1'b1, FC2_OUT1_ADDR, lane1);

    $display("  UB bank1[%0d:%0d] = {lane1:%0d,lane0:%0d}",
             FC2_OUT0_ADDR, FC2_OUT1_ADDR, $signed(lane1), $signed(lane0));
    expect_i8_eq("fc2 output lane0", lane0, 8'sd2);
    expect_i8_eq("fc2 output lane1", lane1, 8'sd4);
  endtask

  initial begin
    init_signals();
    reset_dut();

    preload_fc2_vector();
    run_rom_controller_datapath();
    check_output_buffer();

    $display("test_controller_rom_tile: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_controller_rom_tile failed");
    end
    $finish;
  end

endmodule : test_controller_rom_tile
