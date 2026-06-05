`timescale 1ns / 1ps

`ifndef TPU_SIZE
`define TPU_SIZE 4
`endif

module test_controller_unified_buffer_v2;

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
  localparam int UB_BANK_DEPTH = 64;
  localparam int UB_ADDR_WIDTH = $clog2(UB_BANK_DEPTH);
  localparam int WGT_FIFO_DEPTH = 8;
  localparam int CLK_PERIOD = 10;
  localparam int TIMEOUT_CYCLES = 300;
  localparam int ACC_COUNT_WIDTH = ACC_ADDR_WIDTH + 1;

  localparam logic [1:0] ACT_RELU_MODE = 2'd1;
  localparam int POOL_BYPASS = 0;

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
  logic [31:0] controller_cycle_count_o;
  logic [31:0] controller_error_code_o;

  logic read_bank_i;
  logic write_bank_i;
  logic [UB_ADDR_WIDTH-1:0] input_base_addr_i;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_i;
  logic [ACC_ADDR_WIDTH:0] block_size_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_cfg_i;
  logic signed [(DATA_WIDTH*SIZE)-1:0] weight_bottom_row_i;
  logic signed [(DATA_WIDTH*SIZE)-1:0] weight_top_row_i;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] bias_flatten_i;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_i;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_i;

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

  tpu_controller #(
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
      .dbg_cycle_count_o               (controller_cycle_count_o),
      .dbg_error_code_o                (controller_error_code_o),
      .read_bank_i                     (read_bank_i),
      .write_bank_i                    (write_bank_i),
      .input_base_addr_i               (input_base_addr_i),
      .output_base_addr_i              (output_base_addr_i),
      .block_size_i                    (block_size_i),
      .num_tiles_i                     (num_tiles_cfg_i),
      .weight_bottom_row_i             (weight_bottom_row_i),
      .weight_top_row_i                (weight_top_row_i),
      .act_mode_i                      (ACT_RELU_MODE),
      .bias_flatten_i                  (bias_flatten_i),
      .requant_multiplier_flatten_i    (requant_multiplier_flatten_i),
      .requant_shift_flatten_i         (requant_shift_flatten_i),
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

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_i8_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    pack_i8_pair = {lane1, lane0};
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
    read_bank_i = 1'b0;
    write_bank_i = 1'b1;
    input_base_addr_i = '0;
    output_base_addr_i = UB_ADDR_WIDTH'(10);
    block_size_i = ACC_COUNT_WIDTH'(1);
    num_tiles_cfg_i = TILE_COUNT_WIDTH'(1);
    weight_bottom_row_i = pack_i8_pair(8'sd5, -8'sd7);
    weight_top_row_i = pack_i8_pair(8'sd2, -8'sd3);
    bias_flatten_i = {32'sd5, 32'sd4};
    requant_multiplier_flatten_i = {32'sd16, 32'sd16};
    requant_shift_flatten_i = {6'd4, 6'd4};
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

  task automatic preload_input_vector();
    print_header("TEST: Host preload into unified buffer");
    host_mode = 1'b1;
    host_write(1'b0, UB_ADDR_WIDTH'(0), 8'sd4);
    host_write(1'b0, UB_ADDR_WIDTH'(1), 8'sd6);
    $display("  UB bank0[0:1] = {%0d,%0d}", 4, 6);
  endtask

  task automatic run_controller_datapath();
    int cycles;

    print_header("TEST: Controller -> UB -> TPU datapath");
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

    $display("  CTRL   : done=%b error=%b state=%0d cycles=%0d err=0x%08h",
             controller_done_o, controller_error_o, controller_state_o,
             controller_cycle_count_o, controller_error_code_o);

    expect_flag("controller finished", controller_done_o);
    expect_flag("controller no error", !controller_error_o);
    expect_flag("datapath no overflow", overflow_flatten_w == '0);
  endtask

  task automatic check_output_buffer();
    logic signed [DATA_WIDTH-1:0] lane0;
    logic signed [DATA_WIDTH-1:0] lane1;

    print_header("TEST: Host readback from unified buffer");
    host_mode = 1'b1;
    host_read(1'b1, UB_ADDR_WIDTH'(10), lane0);
    host_read(1'b1, UB_ADDR_WIDTH'(11), lane1);

    $display("  UB bank1[10:11] = {lane1:%0d,lane0:%0d}", $signed(lane1), $signed(lane0));
    expect_i8_eq("output lane0", lane0, 8'sd42);
    expect_i8_eq("output lane1 ReLU clamp", lane1, 8'sd0);
  endtask

  initial begin
    init_signals();
    reset_dut();

    preload_input_vector();
    run_controller_datapath();
    check_output_buffer();

    $display("test_controller_unified_buffer_v2: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_controller_unified_buffer_v2 failed");
    end
    $finish;
  end

endmodule : test_controller_unified_buffer_v2
