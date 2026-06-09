`timescale 1ns / 1ps

module test_tpu_datapath_v2;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = 2;
  localparam int MAX_NUM_TILES = 128;
  localparam int TILE_COUNT_WIDTH = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1;
  localparam int ACC_WIDTH = 32;
  localparam int ACC_DEPTH = 4;
  localparam int ACC_ADDR_WIDTH = $clog2(ACC_DEPTH);
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int REQUANT_MULT_WIDTH = 32;
  localparam int REQUANT_SHIFT_WIDTH = 6;
  localparam int WGT_FIFO_DEPTH = 8;
  localparam int CLK_PERIOD = 10;
  localparam int MAX_OBSERVE_CYCLES = 100;

  localparam int ACT_RELU = 1;
  localparam logic [1:0] ACT_RELU_MODE = 2'd1;
  localparam int POOL_BYPASS = 0;

  logic clk;
  logic rst_n;

  logic work_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_i;

  logic start_wgt_load_i;
  logic wgt_fetcher_ready_o;
  logic [(DATA_WIDTH*SIZE)-1:0] wgt_fifo_wdata_i;
  logic                         wgt_fifo_wr_en_i;
  logic                         wgt_fifo_full_o;
  logic                         wgt_fifo_empty_o;

  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_i;
  logic        [SIZE-1:0]              act_valid_raw_i;

  logic accumulator_clear_all_i;
  logic accumulator_row_clear_i;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_i;
  logic accumulator_write_en_i;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_i;
  logic accumulator_read_en_i;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_i;
  logic vpu_input_done_i;
  logic [1:0]                                   vpu_act_mode_i;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_i;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_i;
  logic [      (REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_i;
  logic signed [ACC_WIDTH-1:0]                 vpu_output_zero_point_i;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_o;
  logic        [SIZE-1:0]                    mxu_psum_valid_o;
  logic                                      psum_packer_busy_o;
  logic        [SIZE-1:0]                    wgt_load_done_o;

  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_o;
  logic                               accumulator_read_valid_o;
  logic                               accumulator_row_done_o;
  logic [ACC_ADDR_WIDTH-1:0]          accumulator_row_done_addr_o;
  logic [ACC_DEPTH-1:0]               accumulator_row_ready_o;

  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_o;
  logic                               vpu_data_valid_o;
  logic                               done_o;

  logic                 overflow_clr_i;
  logic [SIZE*SIZE-1:0] overflow_flatten_o;

  int test_count;
  int pass_count;
  int fail_count;

  datapath #(
      .SIZE             (SIZE),
      .DATA_WIDTH       (DATA_WIDTH),
      .LOCAL_PSUM_WIDTH (LOCAL_PSUM_WIDTH),
      .MAX_NUM_TILES    (MAX_NUM_TILES),
      .ACC_WIDTH        (ACC_WIDTH),
      .ACC_DEPTH        (ACC_DEPTH),
      .ACC_ADDR_WIDTH   (ACC_ADDR_WIDTH),
      .ACT_WIDTH        (ACC_WIDTH),
      .OUT_WIDTH        (OUT_WIDTH),
      .ACT_MODE         (ACT_RELU),
      .QUANT_ENABLE     (1'b1),
      .BIAS_WIDTH       (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH(REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .NORM_SHIFT       (0),
      .NORM_ROUND_ENABLE(1'b1),
      .POOL_MODE        (POOL_BYPASS),
      .POOL_WINDOW      (2),
      .WGT_FIFO_DEPTH   (WGT_FIFO_DEPTH),
      .TILE_COUNT_WIDTH (TILE_COUNT_WIDTH)
  ) dut (
      .clk                             (clk),
      .rst_n                           (rst_n),
      .work_i                          (work_i),
      .num_tiles_i                     (num_tiles_i),
      .start_wgt_load_i                (start_wgt_load_i),
      .wgt_fetcher_ready_o             (wgt_fetcher_ready_o),
      .wgt_fifo_wdata_i                (wgt_fifo_wdata_i),
      .wgt_fifo_wr_en_i                (wgt_fifo_wr_en_i),
      .wgt_fifo_full_o                 (wgt_fifo_full_o),
      .wgt_fifo_empty_o                (wgt_fifo_empty_o),
      .act_flat_raw_i                  (act_flat_raw_i),
      .act_valid_raw_i                 (act_valid_raw_i),
      .accumulator_clear_all_i         (accumulator_clear_all_i),
      .accumulator_row_clear_i         (accumulator_row_clear_i),
      .accumulator_row_clear_addr_i    (accumulator_row_clear_addr_i),
      .accumulator_write_en_i          (accumulator_write_en_i),
      .psum_packer_dbg_counter_clear_i (1'b0),
      .accumulator_write_addr_i        (accumulator_write_addr_i),
      .accumulator_read_en_i           (accumulator_read_en_i),
      .accumulator_read_addr_i         (accumulator_read_addr_i),
      .vpu_input_done_i                (vpu_input_done_i),
      .vpu_act_mode_i                  (vpu_act_mode_i),
      .vpu_bias_flatten_i              (vpu_bias_flatten_i),
      .vpu_requant_multiplier_flatten_i(vpu_requant_multiplier_flatten_i),
      .vpu_requant_shift_flatten_i     (vpu_requant_shift_flatten_i),
      .vpu_output_zero_point_i         (vpu_output_zero_point_i),
      .mxu_psum_flatten_o              (mxu_psum_flatten_o),
      .mxu_psum_valid_o                (mxu_psum_valid_o),
      .psum_packer_busy_o              (psum_packer_busy_o),
      .wgt_load_done_o                 (wgt_load_done_o),
      .accumulator_read_flatten_o      (accumulator_read_flatten_o),
      .accumulator_read_valid_o        (accumulator_read_valid_o),
      .accumulator_row_done_o          (accumulator_row_done_o),
      .accumulator_row_done_addr_o     (accumulator_row_done_addr_o),
      .accumulator_row_ready_o         (accumulator_row_ready_o),
      .vpu_data_flatten_o              (vpu_data_flatten_o),
      .vpu_data_valid_o                (vpu_data_valid_o),
      .done_o                          (done_o),
      .overflow_clr_i                  (overflow_clr_i),
      .overflow_flatten_o              (overflow_flatten_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_data_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    pack_data_pair = {lane1, lane0};
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_mxu_psum(input int lane);
    get_mxu_psum = mxu_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_packed_psum(input int lane);
    get_packed_psum =
        dut.u_psum_packer.packed_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] get_acc_lane(input int lane);
    get_acc_lane = accumulator_read_flatten_o[(lane*ACC_WIDTH)+:ACC_WIDTH];
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] get_vpu_lane(input int lane);
    get_vpu_lane = vpu_data_flatten_o[(lane*OUT_WIDTH)+:OUT_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] extend_psum(
      input logic signed [LOCAL_PSUM_WIDTH-1:0] value_i
  );
    extend_psum = {{(ACC_WIDTH - LOCAL_PSUM_WIDTH) {value_i[LOCAL_PSUM_WIDTH-1]}}, value_i};
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

  task automatic expect_psum_eq(
      input string label,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] actual,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected
  );
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic expect_acc_eq(
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

  task automatic expect_out_eq(
      input string label,
      input logic signed [OUT_WIDTH-1:0] actual,
      input logic signed [OUT_WIDTH-1:0] expected
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
    rst_n                           = 1'b0;
    work_i                          = 1'b0;
    num_tiles_i                     = TILE_COUNT_WIDTH'(NUM_TILES);
    start_wgt_load_i                = 1'b0;
    wgt_fifo_wdata_i                = '0;
    wgt_fifo_wr_en_i                = 1'b0;
    act_flat_raw_i                  = '0;
    act_valid_raw_i                 = '0;
    accumulator_clear_all_i         = 1'b0;
    accumulator_row_clear_i         = 1'b0;
    accumulator_row_clear_addr_i    = '0;
    accumulator_write_en_i          = 1'b0;
    accumulator_write_addr_i        = '0;
    accumulator_read_en_i           = 1'b0;
    accumulator_read_addr_i         = '0;
    vpu_input_done_i                = 1'b0;
    vpu_act_mode_i                  = ACT_RELU_MODE;
    vpu_bias_flatten_i              = {32'sd5, 32'sd4};
    vpu_requant_multiplier_flatten_i = {32'sd16, 32'sd16};
    vpu_requant_shift_flatten_i     = {6'd4, 6'd4};
    vpu_output_zero_point_i         = 32'sd0;
    overflow_clr_i                  = 1'b0;
    test_count                      = 0;
    pass_count                      = 0;
    fail_count                      = 0;
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
  endtask

  task automatic fifo_write_row(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    @(negedge clk);
    wgt_fifo_wdata_i = pack_data_pair(lane0, lane1);
    wgt_fifo_wr_en_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    wgt_fifo_wr_en_i = 1'b0;
    wgt_fifo_wdata_i = '0;
  endtask

  task automatic pulse_start_weight_load();
    @(negedge clk);
    start_wgt_load_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    start_wgt_load_i = 1'b0;
  endtask

  task automatic load_weights_through_fifo();
    logic [SIZE-1:0] done_seen;

    print_header("TEST: TPU datapath weight FIFO/fetcher load");

    done_seen = '0;

    // Bottom row first, then top row, because the fetcher streams through the SA top.
    fifo_write_row(8'sd5, -8'sd7);
    expect_flag("fetcher waits for a full weight tile", wgt_fetcher_ready_o == 1'b0);

    fifo_write_row(8'sd2, -8'sd3);
    expect_flag("fetcher ready after two FIFO rows", wgt_fetcher_ready_o);

    pulse_start_weight_load();
    for (int cycle = 0; cycle < 20; cycle++) begin
      @(posedge clk);
      #1;
      done_seen |= wgt_load_done_o;
    end

    $display("  weights active: W=[[2,-3],[5,-7]]");
    expect_flag("weight stream reached both bottom PEs", done_seen == 2'b11);
    expect_flag("weight FIFO empty after fetch", wgt_fifo_empty_o);
  endtask

  task automatic launch_activation_vector(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    @(negedge clk);
    act_flat_raw_i           = pack_data_pair(lane0, lane1);
    act_valid_raw_i          = 2'b11;
    accumulator_write_addr_i = '0;
    accumulator_write_en_i   = 1'b1;
    work_i                   = 1'b1;
    @(posedge clk);
    #1;
    $display("  launch activation: A={row1:%0d,row0:%0d}", $signed(lane1), $signed(lane0));

    @(negedge clk);
    act_flat_raw_i  = '0;
    act_valid_raw_i = '0;
    work_i          = 1'b0;
  endtask

  task automatic run_activation_tile(
      input logic signed [DATA_WIDTH-1:0] act0,
      input logic signed [DATA_WIDTH-1:0] act1,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected_lane0,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected_lane1,
      input int tile_idx
  );
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_lane1;
    logic [SIZE-1:0] seen;
    logic packed_seen;

    captured_lane0 = '0;
    captured_lane1 = '0;
    seen           = '0;
    packed_seen    = 1'b0;

    launch_activation_vector(act0, act1);

    for (int cycle = 0; cycle < MAX_OBSERVE_CYCLES; cycle++) begin
      @(posedge clk);
      #1;

      if (mxu_psum_valid_o[0] && !seen[0]) begin
        seen[0] = 1'b1;
        captured_lane0 = get_mxu_psum(0);
        $display("  CAPTURE: MXU psum lane0 = %0d", $signed(captured_lane0));
      end

      if (mxu_psum_valid_o[1] && !seen[1]) begin
        seen[1] = 1'b1;
        captured_lane1 = get_mxu_psum(1);
        $display("  CAPTURE: MXU psum lane1 = %0d", $signed(captured_lane1));
      end

      if (dut.u_psum_packer.packed_valid_o && !packed_seen) begin
        packed_seen = 1'b1;
        $display("  PACKED : tile%0d row0 psum={lane1:%0d,lane0:%0d}",
                 tile_idx, $signed(get_packed_psum(1)), $signed(get_packed_psum(0)));
        expect_psum_eq($sformatf("tile%0d packed lane0", tile_idx),
                       get_packed_psum(0), expected_lane0);
        expect_psum_eq($sformatf("tile%0d packed lane1", tile_idx),
                       get_packed_psum(1), expected_lane1);
        expect_flag($sformatf("tile%0d packed address row 0", tile_idx),
                    dut.u_psum_packer.packed_write_addr_o == '0);
        break;
      end
    end

    expect_flag($sformatf("tile%0d MXU produced both psum lanes", tile_idx), seen == 2'b11);
    expect_flag($sformatf("tile%0d packer produced one vector", tile_idx), packed_seen);
    expect_psum_eq($sformatf("tile%0d MXU lane0 psum", tile_idx),
                   captured_lane0, expected_lane0);
    expect_psum_eq($sformatf("tile%0d MXU lane1 psum", tile_idx),
                   captured_lane1, expected_lane1);

    @(negedge clk);
    accumulator_write_en_i = 1'b0;

    // The accumulator samples the packer's registered output on the next clock.
    @(posedge clk);
    #1;
    $display("  ACC WRITE: tile%0d row_done=%b ready=%b",
             tile_idx, accumulator_row_done_o, accumulator_row_ready_o[0]);
  endtask

  task automatic read_accumulator_row();
    print_header("TEST: Accumulator read -> VPU");

    @(negedge clk);
    accumulator_read_addr_i = '0;
    accumulator_read_en_i   = 1'b1;
    vpu_input_done_i        = 1'b1;

    @(posedge clk);
    #1;
    $display("  ACC READ: valid=%b row0={lane1:%0d,lane0:%0d}",
             accumulator_read_valid_o,
             $signed(get_acc_lane(1)), $signed(get_acc_lane(0)));
    expect_flag("accumulator read valid", accumulator_read_valid_o);

    @(negedge clk);
    accumulator_read_en_i = 1'b0;
  endtask

  task automatic wait_vpu_output();
    for (int cycle = 0; cycle < 30; cycle++) begin
      @(posedge clk);
      #1;
      if (vpu_data_valid_o) begin
        $display("  VPU OUT : data={lane1:%0d,lane0:%0d} done=%b",
                 $signed(get_vpu_lane(1)), $signed(get_vpu_lane(0)), done_o);
        expect_flag("VPU output valid", 1'b1);
        return;
      end
    end

    expect_flag("VPU output valid", 1'b0);
  endtask

  task automatic test_full_datapath();
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile0_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile0_lane1;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile1_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile1_lane1;
    logic signed [ACC_WIDTH-1:0] expected_acc0;
    logic signed [ACC_WIDTH-1:0] expected_acc1;

    print_header("TEST: MXU -> psum packer -> accumulator");

    tile0_lane0 = (8'sd4 * 8'sd2) + (8'sd6 * 8'sd5);
    tile0_lane1 = (8'sd4 * -8'sd3) + (8'sd6 * -8'sd7);
    tile1_lane0 = (-8'sd1 * 8'sd2) + (8'sd2 * 8'sd5);
    tile1_lane1 = (-8'sd1 * -8'sd3) + (8'sd2 * -8'sd7);

    expected_acc0 = extend_psum(tile0_lane0) + extend_psum(tile1_lane0);
    expected_acc1 = extend_psum(tile0_lane1) + extend_psum(tile1_lane1);

    run_activation_tile(8'sd4, 8'sd6, tile0_lane0, tile0_lane1, 0);
    expect_flag("accumulator row not ready after first packed tile",
                accumulator_row_ready_o[0] == 1'b0);

    run_activation_tile(-8'sd1, 8'sd2, tile1_lane0, tile1_lane1, 1);
    expect_flag("accumulator asserts row_done after second packed tile",
                accumulator_row_done_o);
    expect_flag("accumulator row_done address is row 0",
                accumulator_row_done_addr_o == '0);
    expect_flag("accumulator row 0 ready", accumulator_row_ready_o[0]);
    expect_flag("no PE overflow in TPU datapath test", overflow_flatten_o == '0);

    read_accumulator_row();
    expect_acc_eq("accumulator lane0 sum", get_acc_lane(0), expected_acc0);
    expect_acc_eq("accumulator lane1 sum", get_acc_lane(1), expected_acc1);

    wait_vpu_output();
    expect_out_eq("VPU lane0 bias + requant with symmetric zero-point", get_vpu_lane(0), 8'sd50);
    expect_out_eq("VPU lane1 bias + requant then ReLU", get_vpu_lane(1), 8'sd0);
    expect_flag("VPU done follows final row", done_o);
  endtask

  initial begin
    init_signals();
    reset_dut();

    load_weights_through_fifo();
    test_full_datapath();

    $display("test_tpu_datapath_v2: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_tpu_datapath_v2 failed");
    end
    $finish;
  end

endmodule : test_tpu_datapath_v2
