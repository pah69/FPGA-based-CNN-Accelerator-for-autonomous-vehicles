`timescale 1ns / 1ps

module test_accumulator_array_ws_sa_vpu;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ROW_STAGGER_CYCLES = 4;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = 2;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;
  localparam int ACC_WIDTH = 32;
  localparam int ACC_DEPTH = 4;
  localparam int ACC_ADDR_WIDTH = $clog2(ACC_DEPTH);
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int REQUANT_MULT_WIDTH = 32;
  localparam int REQUANT_SHIFT_WIDTH = 6;
  localparam int CLK_PERIOD = 10;
  localparam int MAX_OBSERVE_CYCLES = 80;

  localparam int ACT_RELU = 1;
  localparam logic [1:0] ACT_RELU_MODE = 2'd1;
  localparam int POOL_BYPASS = 0;

  logic clk;
  logic rst_n;

  logic work_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_i;

  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_i;
  logic        [SIZE-1:0]              act_valid_raw_i;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_skewed_o;
  logic        [SIZE-1:0]              act_valid_skewed_o;

  logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i;
  logic        [SIZE-1:0]              wgt_load_i;
  logic                                weight_switch_i;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] sa_psum_flatten_o;
  logic        [SIZE-1:0]                    sa_psum_valid_o;
  logic signed [(ACC_WIDTH*SIZE)-1:0]        unused_sa_result_o;
  logic                                      unused_sa_done_o;
  logic        [SIZE-1:0]                    wgt_load_done_o;
  logic        [SIZE*SIZE-1:0]               overflow_flatten_o;
  logic                                      overflow_clr_i;

  logic clear_all_i;
  logic row_clear_i;
  logic [ACC_ADDR_WIDTH-1:0] row_clear_addr_i;
  logic acc_write_en_i;
  logic [ACC_ADDR_WIDTH-1:0] acc_write_addr_i;
  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] acc_psum_flatten_i;
  logic        [SIZE-1:0]                    acc_psum_valid_i;
  logic acc_read_en_i;
  logic [ACC_ADDR_WIDTH-1:0] acc_read_addr_i;
  logic signed [(ACC_WIDTH*SIZE)-1:0] acc_read_data_o;
  logic                              acc_read_valid_o;
  logic                              acc_row_done_o;
  logic [ACC_ADDR_WIDTH-1:0]         acc_row_done_addr_o;
  logic [ACC_DEPTH-1:0]              acc_row_ready_o;

  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_o;
  logic                               vpu_valid_o;
  logic                               vpu_done_o;

  logic signed [(BIAS_WIDTH*SIZE)-1:0]         unused_bias_i;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] unused_mult_i;
  logic [      (REQUANT_SHIFT_WIDTH*SIZE)-1:0] unused_shift_i;
  logic signed [ACC_WIDTH-1:0]                 unused_zero_point_i;

  int test_count;
  int pass_count;
  int fail_count;

  act_skew_buffer #(
      .SIZE              (SIZE),
      .DATA_WIDTH        (DATA_WIDTH),
      .ROW_STAGGER_CYCLES(ROW_STAGGER_CYCLES)
  ) u_skew_buffer (
      .clk               (clk),
      .rst_n             (rst_n),
      .act_flat_raw_i    (act_flat_raw_i),
      .act_valid_raw_i   (act_valid_raw_i),
      .act_skewed_o      (act_skewed_o),
      .act_valid_skewed_o(act_valid_skewed_o)
  );

  systolic_array #(
      .SIZE              (SIZE),
      .DATA_WIDTH        (DATA_WIDTH),
      .LOCAL_PSUM_WIDTH  (LOCAL_PSUM_WIDTH),
      .NUM_TILES         (NUM_TILES),
      .ACC_WIDTH         (ACC_WIDTH),
      .ENABLE_LOCAL_ACCUM(1'b0),
      .TILE_COUNT_WIDTH  (TILE_COUNT_WIDTH)
  ) u_systolic_array (
      .clk               (clk),
      .rst_n             (rst_n),
      .work_i            (work_i),
      .num_tiles_i       (num_tiles_i),
      .wgt_flatten_i     (wgt_flatten_i),
      .wgt_load_i        (wgt_load_i),
      .weight_switch_i   (weight_switch_i),
      .act_flatten_i     (act_skewed_o),
      .act_valid_i       (act_valid_skewed_o),
      .psum_flatten_o    (sa_psum_flatten_o),
      .psum_valid_o      (sa_psum_valid_o),
      .result_flatten_o  (unused_sa_result_o),
      .done_o            (unused_sa_done_o),
      .wgt_load_done_o   (wgt_load_done_o),
      .overflow_clr_i    (overflow_clr_i),
      .overflow_flatten_o(overflow_flatten_o)
  );

  accumulator_array #(
      .SIZE            (SIZE),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .ACC_WIDTH       (ACC_WIDTH),
      .DEPTH           (ACC_DEPTH),
      .ADDR_WIDTH      (ACC_ADDR_WIDTH),
      .NUM_TILES       (NUM_TILES),
      .TILE_COUNT_WIDTH(TILE_COUNT_WIDTH)
  ) u_accumulator_array (
      .clk                (clk),
      .rst_n              (rst_n),
      .clear_all_i        (clear_all_i),
      .num_tiles_i        (num_tiles_i),
      .row_clear_i        (row_clear_i),
      .row_clear_addr_i   (row_clear_addr_i),
      .write_en_i         (acc_write_en_i),
      .write_addr_i       (acc_write_addr_i),
      .psum_flatten_i     (acc_psum_flatten_i),
      .psum_valid_i       (acc_psum_valid_i),
      .read_en_i          (acc_read_en_i),
      .read_addr_i        (acc_read_addr_i),
      .read_data_flatten_o(acc_read_data_o),
      .read_valid_o       (acc_read_valid_o),
      .row_done_o         (acc_row_done_o),
      .row_done_addr_o    (acc_row_done_addr_o),
      .row_ready_o        (acc_row_ready_o)
  );

  vector_processing_unit #(
      .SIZE             (SIZE),
      .ACC_WIDTH        (ACC_WIDTH),
      .ACT_WIDTH        (ACC_WIDTH),
      .OUT_WIDTH        (OUT_WIDTH),
      .ACT_MODE         (ACT_RELU),
      .NORM_SHIFT       (1),
      .NORM_ROUND_ENABLE(1'b1),
      .POOL_MODE        (POOL_BYPASS),
      .POOL_WINDOW      (2)
  ) u_vpu (
      .clk           (clk),
      .rst_n         (rst_n),
      .acc_flatten_i (acc_read_data_o),
      .acc_valid_i   (acc_read_valid_o),
      .done_i        (acc_read_valid_o),
      .act_mode_i    (ACT_RELU_MODE),
      .bias_flatten_i(unused_bias_i),
      .requant_multiplier_flatten_i(unused_mult_i),
      .requant_shift_flatten_i     (unused_shift_i),
      .output_zero_point_i         (unused_zero_point_i),
      .data_flatten_o(vpu_data_o),
      .data_valid_o  (vpu_valid_o),
      .done_o        (vpu_done_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  assign unused_bias_i       = '0;
  assign unused_mult_i       = '0;
  assign unused_shift_i      = '0;
  assign unused_zero_point_i = '0;

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_data_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    pack_data_pair = {lane1, lane0};
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_sa_psum(input int lane);
    get_sa_psum = sa_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] get_acc_lane(input int lane);
    get_acc_lane = acc_read_data_o[(lane*ACC_WIDTH)+:ACC_WIDTH];
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] get_vpu_lane(input int lane);
    get_vpu_lane = vpu_data_o[(lane*OUT_WIDTH)+:OUT_WIDTH];
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
    rst_n              = 1'b0;
    work_i             = 1'b0;
    num_tiles_i        = TILE_COUNT_WIDTH'(NUM_TILES);
    act_flat_raw_i     = '0;
    act_valid_raw_i    = '0;
    wgt_flatten_i      = '0;
    wgt_load_i         = '0;
    weight_switch_i    = 1'b0;
    overflow_clr_i     = 1'b0;
    clear_all_i        = 1'b0;
    row_clear_i        = 1'b0;
    row_clear_addr_i   = '0;
    acc_write_en_i     = 1'b0;
    acc_write_addr_i   = '0;
    acc_psum_flatten_i = '0;
    acc_psum_valid_i   = '0;
    acc_read_en_i      = 1'b0;
    acc_read_addr_i    = '0;
    test_count         = 0;
    pass_count         = 0;
    fail_count         = 0;
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
  endtask

  task automatic drive_weight_cycle(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1,
      input logic [SIZE-1:0]              load_mask,
      input logic                         switch_weights
  );
    @(negedge clk);
    wgt_flatten_i   = pack_data_pair(lane0, lane1);
    wgt_load_i      = load_mask;
    weight_switch_i = switch_weights;
    @(posedge clk);
    #1;
  endtask

  task automatic load_direct_weights();
    logic [SIZE-1:0] done_seen;

    print_header("TEST: Load weights into WS systolic array");

    done_seen = '0;

    // Bottom row first, then top row, because weights move top to bottom.
    drive_weight_cycle(8'sd5, -8'sd7, 2'b11, 1'b0);
    done_seen |= wgt_load_done_o;
    drive_weight_cycle(8'sd2, -8'sd3, 2'b11, 1'b0);
    done_seen |= wgt_load_done_o;
    drive_weight_cycle('0, '0, '0, 1'b1);
    done_seen |= wgt_load_done_o;
    drive_weight_cycle('0, '0, '0, 1'b0);
    done_seen |= wgt_load_done_o;

    $display("  weights active: W=[[2,-3],[5,-7]]");
    expect_flag("weight stream reached both bottom PEs", done_seen == 2'b11);
  endtask

  task automatic launch_activation_vector(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    @(negedge clk);
    act_flat_raw_i  = pack_data_pair(lane0, lane1);
    act_valid_raw_i = 2'b11;
    work_i          = 1'b1;
    @(posedge clk);
    #1;
    $display("  launch activation: A={row1:%0d,row0:%0d}", $signed(lane1), $signed(lane0));

    @(negedge clk);
    act_flat_raw_i  = '0;
    act_valid_raw_i = '0;
    work_i          = 1'b0;
  endtask

  task automatic capture_sa_vector(
      output logic signed [LOCAL_PSUM_WIDTH-1:0] lane0,
      output logic signed [LOCAL_PSUM_WIDTH-1:0] lane1
  );
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured[0:SIZE-1];
    logic [SIZE-1:0] seen;

    seen = '0;
    for (int lane = 0; lane < SIZE; lane++) begin
      captured[lane] = '0;
    end

    for (int cycle = 0; cycle < MAX_OBSERVE_CYCLES; cycle++) begin
      @(posedge clk);
      #1;

      for (int lane = 0; lane < SIZE; lane++) begin
        if (sa_psum_valid_o[lane] && !seen[lane]) begin
          seen[lane] = 1'b1;
          captured[lane] = get_sa_psum(lane);
          $display("  CAPTURE: SA psum lane%0d = %0d", lane, $signed(get_sa_psum(lane)));
        end
      end

      if (&seen) begin
        lane0 = captured[0];
        lane1 = captured[1];
        expect_flag("SA produced both psum lanes", 1'b1);
        return;
      end
    end

    lane0 = captured[0];
    lane1 = captured[1];
    expect_flag("SA produced both psum lanes", 1'b0);
  endtask

  task automatic write_accumulator_vector(
      input logic signed [LOCAL_PSUM_WIDTH-1:0] lane0,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] lane1,
      input int tile_idx
  );
    @(negedge clk);
    acc_psum_flatten_i[(0*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = lane0;
    acc_psum_flatten_i[(1*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = lane1;
    acc_psum_valid_i = 2'b11;
    acc_write_addr_i = '0;
    acc_write_en_i   = 1'b1;

    @(posedge clk);
    #1;
    $display("  ACC WRITE: tile%0d row0 psum={lane1:%0d,lane0:%0d} row_done=%b ready=%b",
             tile_idx, $signed(lane1), $signed(lane0), acc_row_done_o, acc_row_ready_o[0]);

    @(negedge clk);
    acc_psum_flatten_i = '0;
    acc_psum_valid_i   = '0;
    acc_write_en_i     = 1'b0;
  endtask

  task automatic run_sa_tile_and_write_accumulator(
      input logic signed [DATA_WIDTH-1:0] act0,
      input logic signed [DATA_WIDTH-1:0] act1,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected_lane0,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected_lane1,
      input int tile_idx
  );
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_lane1;

    launch_activation_vector(act0, act1);
    capture_sa_vector(captured_lane0, captured_lane1);

    expect_psum_eq($sformatf("tile%0d SA lane0 psum", tile_idx), captured_lane0, expected_lane0);
    expect_psum_eq($sformatf("tile%0d SA lane1 psum", tile_idx), captured_lane1, expected_lane1);

    write_accumulator_vector(captured_lane0, captured_lane1, tile_idx);
  endtask

  task automatic read_accumulator_row();
    print_header("TEST: Read accumulated row into VPU");

    @(negedge clk);
    acc_read_addr_i = '0;
    acc_read_en_i   = 1'b1;
    @(posedge clk);
    #1;
    if (acc_read_valid_o) begin
      $display("  ACC READ: row0={lane1:%0d,lane0:%0d}",
               $signed(get_acc_lane(1)), $signed(get_acc_lane(0)));
      expect_flag("accumulator read valid", 1'b1);
    end else begin
      expect_flag("accumulator read valid", 1'b0);
    end

    @(negedge clk);
    acc_read_en_i = 1'b0;
  endtask

  task automatic wait_vpu_output();
    for (int cycle = 0; cycle < 30; cycle++) begin
      @(posedge clk);
      #1;
      if (vpu_valid_o) begin
        $display("  VPU OUT : data={lane1:%0d,lane0:%0d} done=%b",
                 $signed(get_vpu_lane(1)), $signed(get_vpu_lane(0)), vpu_done_o);
        expect_flag("VPU output valid", 1'b1);
        return;
      end
    end

    expect_flag("VPU output valid", 1'b0);
  endtask

  task automatic test_sa_accumulator_vpu_flow();
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile0_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile0_lane1;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile1_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile1_lane1;
    logic signed [ACC_WIDTH-1:0] expected_acc0;
    logic signed [ACC_WIDTH-1:0] expected_acc1;

    print_header("TEST: WS SA -> accumulator array");

    tile0_lane0 = (8'sd4 * 8'sd2) + (8'sd6 * 8'sd5);
    tile0_lane1 = (8'sd4 * -8'sd3) + (8'sd6 * -8'sd7);
    tile1_lane0 = (-8'sd1 * 8'sd2) + (8'sd2 * 8'sd5);
    tile1_lane1 = (-8'sd1 * -8'sd3) + (8'sd2 * -8'sd7);

    expected_acc0 = extend_psum(tile0_lane0) + extend_psum(tile1_lane0);
    expected_acc1 = extend_psum(tile0_lane1) + extend_psum(tile1_lane1);

    run_sa_tile_and_write_accumulator(8'sd4, 8'sd6, tile0_lane0, tile0_lane1, 0);
    expect_flag("accumulator row not ready after first tile", acc_row_ready_o[0] == 1'b0);

    run_sa_tile_and_write_accumulator(-8'sd1, 8'sd2, tile1_lane0, tile1_lane1, 1);
    expect_flag("accumulator asserts row_done after second tile", acc_row_done_o);
    expect_flag("accumulator row_done address is row 0", acc_row_done_addr_o == '0);
    expect_flag("accumulator row 0 ready", acc_row_ready_o[0]);
    expect_flag("no PE overflow in accumulator integration test", overflow_flatten_o == '0);

    read_accumulator_row();
    expect_acc_eq("accumulator lane0 sum", get_acc_lane(0), expected_acc0);
    expect_acc_eq("accumulator lane1 sum", get_acc_lane(1), expected_acc1);

    wait_vpu_output();
    expect_out_eq("VPU lane0 ReLU rounded >> 1", get_vpu_lane(0), 8'sd23);
    expect_out_eq("VPU lane1 ReLU clamps negative sum", get_vpu_lane(1), 8'sd0);
    expect_flag("VPU done follows final accumulator row", vpu_done_o);
  endtask

  initial begin
    init_signals();
    reset_dut();
    load_direct_weights();

    test_sa_accumulator_vpu_flow();

    $display("test_accumulator_array_ws_sa_vpu: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_accumulator_array_ws_sa_vpu failed");
    end
    $finish;
  end

endmodule : test_accumulator_array_ws_sa_vpu
