`timescale 1ns / 1ps

module test_sa_2x2_computation;

  localparam int SIZE = 2;
  localparam int MAX_ACT_ROWS = 3;
  localparam int DATA_WIDTH = 8;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = MAX_ACT_ROWS;
  localparam int ACC_WIDTH = 32;
  localparam int CLK_PERIOD = 10;
  localparam int ACT_STAGGER_CYCLES = 4;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;
  localparam int NUM_CASES = 5;

  logic clk;
  logic rst_n;
  logic work_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_i;

  logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i;
  logic        [SIZE-1:0]              wgt_load_i;
  logic                                weight_switch_i;

  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_i;
  logic        [SIZE-1:0]              act_valid_i;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o;
  logic        [SIZE-1:0]                    psum_valid_o;
  logic signed [(ACC_WIDTH*SIZE)-1:0]        result_flatten_o;
  logic                                      done_o;
  logic        [SIZE-1:0]                    wgt_load_done_o;

  logic                 overflow_clr_i;
  logic [SIZE*SIZE-1:0] overflow_flatten_o;

  logic signed [DATA_WIDTH-1:0]       weight_matrix[0:SIZE-1][0:SIZE-1];
  logic signed [DATA_WIDTH-1:0]       act_matrix[0:MAX_ACT_ROWS-1][0:SIZE-1];
  logic signed [LOCAL_PSUM_WIDTH-1:0] expected_y[0:MAX_ACT_ROWS-1][0:SIZE-1];
  logic signed [LOCAL_PSUM_WIDTH-1:0] actual_y[0:MAX_ACT_ROWS-1][0:SIZE-1];
  logic signed [ACC_WIDTH-1:0]        expected_acc[0:SIZE-1];

  string case_name;
  int    case_act_rows;

  int cycle_count;
  int test_count;
  int pass_count;
  int fail_count;
  int out_count[0:SIZE-1];
  logic capture_enabled;
  int   capture_goal_rows;

  systolic_array #(
      .SIZE(SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .NUM_TILES(NUM_TILES),
      .ACC_WIDTH(ACC_WIDTH),
      .TILE_COUNT_WIDTH(TILE_COUNT_WIDTH),
      .ENABLE_LOCAL_ACCUM(1'b1)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .work_i(work_i),
      .num_tiles_i(num_tiles_i),
      .wgt_flatten_i(wgt_flatten_i),
      .wgt_load_i(wgt_load_i),
      .weight_switch_i(weight_switch_i),
      .act_flatten_i(act_flatten_i),
      .act_valid_i(act_valid_i),
      .psum_flatten_o(psum_flatten_o),
      .psum_valid_o(psum_valid_o),
      .result_flatten_o(result_flatten_o),
      .done_o(done_o),
      .wgt_load_done_o(wgt_load_done_o),
      .overflow_clr_i(overflow_clr_i),
      .overflow_flatten_o(overflow_flatten_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  initial begin
    // $dumpfile("test_sa_2x2_computation.vcd");
    // $dumpvars(0, test_sa_2x2_computation);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int col = 0; col < SIZE; col++) begin
        out_count[col] <= 0;
      end
    end else if (capture_enabled) begin
      for (int col = 0; col < SIZE; col++) begin
        if (psum_valid_o[col] && (out_count[col] < capture_goal_rows)) begin
          actual_y[out_count[col]][col] <= get_psum_col(col);
          out_count[col] <= out_count[col] + 1;
        end
      end
    end
  end

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_data_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    pack_data_pair = {lane1, lane0};
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_psum_col(input int col);
    case (col)
      0: get_psum_col = psum_flatten_o[(0*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
      default: get_psum_col = psum_flatten_o[(1*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
    endcase
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] get_acc_col(input int col);
    case (col)
      0: get_acc_col = result_flatten_o[(0*ACC_WIDTH)+:ACC_WIDTH];
      default: get_acc_col = result_flatten_o[(1*ACC_WIDTH)+:ACC_WIDTH];
    endcase
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] dot_product_2(
      input logic signed [DATA_WIDTH-1:0] a0,
      input logic signed [DATA_WIDTH-1:0] a1,
      input logic signed [DATA_WIDTH-1:0] w0,
      input logic signed [DATA_WIDTH-1:0] w1
  );
    logic signed [LOCAL_PSUM_WIDTH-1:0] term0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] term1;
    begin
      term0 = a0 * w0;
      term1 = a1 * w1;
      dot_product_2 = term0 + term1;
    end
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
      $display("  FAIL: %s", label);
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
      $display("  FAIL: %s -> got %0d expected %0d", label, $signed(actual), $signed(expected));
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
      $display("  FAIL: %s -> got %0d expected %0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic clear_outputs();
    for (int row = 0; row < MAX_ACT_ROWS; row++) begin
      for (int col = 0; col < SIZE; col++) begin
        actual_y[row][col] = '0;
      end
    end

    for (int col = 0; col < SIZE; col++) begin
      out_count[col] = 0;
    end
  endtask

  task automatic start_capture(input int goal_rows);
    capture_goal_rows = goal_rows;
    capture_enabled   = 1'b1;
  endtask

  task automatic stop_capture();
    capture_enabled = 1'b0;
  endtask

  task automatic clear_case_data();
    case_name = "";
    case_act_rows = 0;

    for (int row = 0; row < SIZE; row++) begin
      for (int col = 0; col < SIZE; col++) begin
        weight_matrix[row][col] = '0;
      end
    end

    for (int row = 0; row < MAX_ACT_ROWS; row++) begin
      for (int col = 0; col < SIZE; col++) begin
        act_matrix[row][col] = '0;
        expected_y[row][col] = '0;
      end
    end

    for (int col = 0; col < SIZE; col++) begin
      expected_acc[col] = '0;
    end
  endtask

  task automatic init_signals();
    rst_n           = 1'b0;
    work_i          = 1'b0;
    num_tiles_i     = TILE_COUNT_WIDTH'(NUM_TILES);
    wgt_flatten_i   = '0;
    wgt_load_i      = '0;
    weight_switch_i = 1'b0;
    act_flatten_i   = '0;
    act_valid_i     = '0;
    overflow_clr_i  = 1'b0;
    capture_enabled = 1'b0;
    capture_goal_rows = 0;

    cycle_count = 0;
    test_count  = 0;
    pass_count  = 0;
    fail_count  = 0;
    clear_outputs();
    clear_case_data();
  endtask

  task automatic reset_dut();
    work_i          = 1'b0;
    num_tiles_i     = TILE_COUNT_WIDTH'(NUM_TILES);
    wgt_flatten_i   = '0;
    wgt_load_i      = '0;
    weight_switch_i = 1'b0;
    act_flatten_i   = '0;
    act_valid_i     = '0;
    overflow_clr_i  = 1'b0;
    capture_enabled = 1'b0;
    capture_goal_rows = 0;
    clear_outputs();

    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  task automatic build_expected();
    for (int row = 0; row < case_act_rows; row++) begin
      for (int col = 0; col < SIZE; col++) begin
        expected_y[row][col] = dot_product_2(
            act_matrix[row][0],
            act_matrix[row][1],
            weight_matrix[0][col],
            weight_matrix[1][col]
        );
      end
    end

    for (int col = 0; col < SIZE; col++) begin
      expected_acc[col] = '0;
      for (int row = 0; row < case_act_rows; row++) begin
        expected_acc[col] += expected_y[row][col];
      end
    end
  endtask

  task automatic configure_case(input int case_id);
    clear_case_data();

    case (case_id)
      0: begin
        case_name = "baseline_3rows";
        case_act_rows = 3;
        weight_matrix[0][0] = 8'sd5;
        weight_matrix[0][1] = -8'sd2;
        weight_matrix[1][0] = 8'sd7;
        weight_matrix[1][1] = 8'sd3;

        act_matrix[0][0] = 8'sd1;
        act_matrix[0][1] = 8'sd2;
        act_matrix[1][0] = -8'sd3;
        act_matrix[1][1] = 8'sd4;
        act_matrix[2][0] = 8'sd2;
        act_matrix[2][1] = -8'sd1;
      end

      1: begin
        case_name = "single_row";
        case_act_rows = 1;
        weight_matrix[0][0] = -8'sd3;
        weight_matrix[0][1] = 8'sd6;
        weight_matrix[1][0] = 8'sd5;
        weight_matrix[1][1] = -8'sd2;

        act_matrix[0][0] = 8'sd0;
        act_matrix[0][1] = 8'sd7;
      end

      2: begin
        case_name = "two_rows_mixed";
        case_act_rows = 2;
        weight_matrix[0][0] = 8'sd4;
        weight_matrix[0][1] = -8'sd1;
        weight_matrix[1][0] = 8'sd2;
        weight_matrix[1][1] = 8'sd3;

        act_matrix[0][0] = 8'sd2;
        act_matrix[0][1] = -8'sd5;
        act_matrix[1][0] = -8'sd1;
        act_matrix[1][1] = 8'sd4;
      end

      3: begin
        case_name = "identity_weights";
        case_act_rows = 3;
        weight_matrix[0][0] = 8'sd1;
        weight_matrix[0][1] = 8'sd0;
        weight_matrix[1][0] = 8'sd0;
        weight_matrix[1][1] = 8'sd1;

        act_matrix[0][0] = 8'sd3;
        act_matrix[0][1] = -8'sd2;
        act_matrix[1][0] = -8'sd4;
        act_matrix[1][1] = 8'sd5;
        act_matrix[2][0] = 8'sd0;
        act_matrix[2][1] = 8'sd7;
      end

      default: begin
        case_name = "zero_column";
        case_act_rows = 3;
        weight_matrix[0][0] = 8'sd0;
        weight_matrix[0][1] = -8'sd4;
        weight_matrix[1][0] = 8'sd0;
        weight_matrix[1][1] = 8'sd2;

        act_matrix[0][0] = 8'sd6;
        act_matrix[0][1] = 8'sd1;
        act_matrix[1][0] = -8'sd2;
        act_matrix[1][1] = 8'sd3;
        act_matrix[2][0] = 8'sd1;
        act_matrix[2][1] = -8'sd4;
      end
    endcase

    num_tiles_i = TILE_COUNT_WIDTH'(case_act_rows);
    build_expected();
  endtask

  task automatic print_case_start(input int case_id);
    $display("CASE %0d: %s rows=%0d exp_acc={%0d,%0d}",
             case_id,
             case_name,
             case_act_rows,
             $signed(expected_acc[0]),
             $signed(expected_acc[1]));
  endtask

  task automatic print_case_debug();
    $display("  W:");
    for (int row = 0; row < SIZE; row++) begin
      $display("    [%0d %0d]", $signed(weight_matrix[row][0]), $signed(weight_matrix[row][1]));
    end

    $display("  A:");
    for (int row = 0; row < case_act_rows; row++) begin
      $display("    [%0d %0d]", $signed(act_matrix[row][0]), $signed(act_matrix[row][1]));
    end

    $display("  Expected Y / Actual Y:");
    for (int row = 0; row < case_act_rows; row++) begin
      $display("    exp[%0d]=[%0d %0d] act[%0d]=[%0d %0d]",
               row,
               $signed(expected_y[row][0]),
               $signed(expected_y[row][1]),
               row,
               $signed(actual_y[row][0]),
               $signed(actual_y[row][1]));
    end

    $display("  Acc exp={%0d,%0d} act={%0d,%0d}",
             $signed(expected_acc[0]),
             $signed(expected_acc[1]),
             $signed(get_acc_col(0)),
             $signed(get_acc_col(1)));
  endtask

  task automatic set_weight_tile(
      input logic signed [DATA_WIDTH-1:0] w00,
      input logic signed [DATA_WIDTH-1:0] w01,
      input logic signed [DATA_WIDTH-1:0] w10,
      input logic signed [DATA_WIDTH-1:0] w11
  );
    weight_matrix[0][0] = w00;
    weight_matrix[0][1] = w01;
    weight_matrix[1][0] = w10;
    weight_matrix[1][1] = w11;
  endtask

  task automatic drive_weight_cycle(
      input logic signed [(DATA_WIDTH*SIZE)-1:0] next_wgt_flatten,
      input logic [SIZE-1:0] next_wgt_load,
      input logic next_weight_switch
  );
    @(negedge clk);
    wgt_flatten_i   = next_wgt_flatten;
    wgt_load_i      = next_wgt_load;
    weight_switch_i = next_weight_switch;
    act_flatten_i   = '0;
    act_valid_i     = '0;
    work_i          = 1'b0;
    @(posedge clk);
  endtask

  task automatic drive_activation_cycle(
      input logic signed [(DATA_WIDTH*SIZE)-1:0] next_act_flatten,
      input logic [SIZE-1:0] next_act_valid,
      input logic next_work
  );
    @(negedge clk);
    act_flatten_i   = next_act_flatten;
    act_valid_i     = next_act_valid;
    work_i          = next_work;
    wgt_flatten_i   = '0;
    wgt_load_i      = '0;
    weight_switch_i = 1'b0;
    @(posedge clk);
  endtask

  task automatic load_weights_and_switch(output logic [SIZE-1:0] done_seen);
    done_seen = '0;

    drive_weight_cycle(pack_data_pair(weight_matrix[1][0], weight_matrix[1][1]), 2'b11, 1'b0);
    done_seen |= wgt_load_done_o;

    drive_weight_cycle(pack_data_pair(weight_matrix[0][0], weight_matrix[0][1]), 2'b11, 1'b0);
    done_seen |= wgt_load_done_o;

    drive_weight_cycle('0, '0, 1'b1);
    done_seen |= wgt_load_done_o;

    drive_weight_cycle('0, '0, 1'b0);
    done_seen |= wgt_load_done_o;
  endtask

  task automatic stream_activation_matrix();
    for (int step = 0; step < case_act_rows + ACT_STAGGER_CYCLES; step++) begin
      logic signed [(DATA_WIDTH*SIZE)-1:0] next_act_flatten;
      logic        [SIZE-1:0]              next_act_valid;
      logic                                next_work;

      next_act_flatten = '0;
      next_act_valid   = '0;
      next_work        = (step == 0);

      // Row m uses A[m][0] on lane 0 and A[m][1] on lane 1 after stagger.
      if (step < case_act_rows) begin
        next_act_flatten[(0*DATA_WIDTH)+:DATA_WIDTH] = act_matrix[step][0];
        next_act_valid[0] = 1'b1;
      end

      if ((step >= ACT_STAGGER_CYCLES) && (step < ACT_STAGGER_CYCLES + case_act_rows)) begin
        next_act_flatten[(1*DATA_WIDTH)+:DATA_WIDTH] = act_matrix[step-ACT_STAGGER_CYCLES][1];
        next_act_valid[1] = 1'b1;
      end

      drive_activation_cycle(next_act_flatten, next_act_valid, next_work);

      if (step == 0) begin
        $display("  start_cycle=%0d", cycle_count);
      end
    end

    drive_activation_cycle('0, '0, 1'b0);
  endtask

  task automatic stream_one_pair(
      input logic signed [DATA_WIDTH-1:0] lane0_value,
      input logic signed [DATA_WIDTH-1:0] lane1_value,
      input logic                         start_work
  );
    drive_activation_cycle(pack_data_pair(lane0_value, '0), 2'b01, start_work);
    repeat (ACT_STAGGER_CYCLES - 1) begin
      drive_activation_cycle('0, '0, 1'b0);
    end
    drive_activation_cycle(pack_data_pair('0, lane1_value), 2'b10, 1'b0);
    drive_activation_cycle('0, '0, 1'b0);
  endtask

  task automatic observe_results();
    logic done_seen;
    int timeout_cycles;

    done_seen = 1'b0;
    timeout_cycles = 0;

    while ((((out_count[0] < capture_goal_rows) || (out_count[1] < capture_goal_rows)) || !done_seen)
           && (timeout_cycles < 60)) begin
      @(posedge clk);

      if (!done_seen && done_o) begin
        done_seen = 1'b1;
        $display("  acc_done result={%0d,%0d}",
                 $signed(get_acc_col(0)),
                 $signed(get_acc_col(1)));
      end

      timeout_cycles++;
    end

    expect_flag("column 0 produced all streamed outputs", out_count[0] == capture_goal_rows);
    expect_flag("column 1 produced all streamed outputs", out_count[1] == capture_goal_rows);
    expect_flag("local accumulator done asserted", done_seen);
  endtask

  task automatic check_results();
    for (int row = 0; row < case_act_rows; row++) begin
      expect_psum_eq($sformatf("Y[%0d][0]", row), actual_y[row][0], expected_y[row][0]);
      expect_psum_eq($sformatf("Y[%0d][1]", row), actual_y[row][1], expected_y[row][1]);
    end

    expect_acc_eq("Accumulated col0", get_acc_col(0), expected_acc[0]);
    expect_acc_eq("Accumulated col1", get_acc_col(1), expected_acc[1]);
    expect_flag("overflow stayed clear", overflow_flatten_o == '0);
  endtask

  task automatic run_case(input int case_id);
    logic [SIZE-1:0] done_seen;
    int fail_before;

    reset_dut();
    configure_case(case_id);
    print_case_start(case_id);
    fail_before = fail_count;
    load_weights_and_switch(done_seen);
    expect_flag("weight load reached bottom row before compute", done_seen == 2'b11);

    clear_outputs();
    start_capture(case_act_rows);
    stream_activation_matrix();
    observe_results();
    stop_capture();
    check_results();

    if (fail_count == fail_before) begin
      $display("  PASS: %s", case_name);
    end else begin
      print_case_debug();
    end
  endtask

  task automatic test_k_tiling_case();
    logic [SIZE-1:0] done_seen;
    int fail_before;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial0_col0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial0_col1;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial1_col0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial1_col1;
    logic signed [ACC_WIDTH-1:0]        final_col0;
    logic signed [ACC_WIDTH-1:0]        final_col1;

    reset_dut();
    case_name = "k_tiling_1x4_x_4x2";
    case_act_rows = 2;
    num_tiles_i = TILE_COUNT_WIDTH'(2);

    partial0_col0 = dot_product_2(8'sd1, 8'sd2, 8'sd5, 8'sd7);
    partial0_col1 = dot_product_2(8'sd1, 8'sd2, -8'sd2, 8'sd3);
    partial1_col0 = dot_product_2(-8'sd3, 8'sd4, 8'sd1, -8'sd6);
    partial1_col1 = dot_product_2(-8'sd3, 8'sd4, 8'sd4, 8'sd2);
    final_col0    = partial0_col0 + partial1_col0;
    final_col1    = partial0_col1 + partial1_col1;

    $display("CASE 5: %s exp_acc={%0d,%0d}",
             case_name, $signed(final_col0), $signed(final_col1));
    fail_before = fail_count;

    set_weight_tile(8'sd5, -8'sd2, 8'sd7, 8'sd3);
    load_weights_and_switch(done_seen);
    expect_flag("tile 0 weight load reached bottom row", done_seen == 2'b11);

    clear_outputs();
    start_capture(2);
    stream_one_pair(8'sd1, 8'sd2, 1'b1);

    set_weight_tile(8'sd1, 8'sd4, -8'sd6, 8'sd2);
    load_weights_and_switch(done_seen);
    expect_flag("tile 1 weight load reached bottom row", done_seen == 2'b11);
    stream_one_pair(-8'sd3, 8'sd4, 1'b0);

    observe_results();
    stop_capture();

    expect_psum_eq("partial[0][0]", actual_y[0][0], partial0_col0);
    expect_psum_eq("partial[0][1]", actual_y[0][1], partial0_col1);
    expect_psum_eq("partial[1][0]", actual_y[1][0], partial1_col0);
    expect_psum_eq("partial[1][1]", actual_y[1][1], partial1_col1);
    expect_acc_eq("final col0", get_acc_col(0), final_col0);
    expect_acc_eq("final col1", get_acc_col(1), final_col1);
    expect_flag("overflow stayed clear", overflow_flatten_o == '0);

    if (fail_count == fail_before) begin
      $display("  PASS: %s", case_name);
    end else begin
      $display("  Partial exp={[%0d %0d] [%0d %0d]} act={[%0d %0d] [%0d %0d]}",
               $signed(partial0_col0), $signed(partial0_col1),
               $signed(partial1_col0), $signed(partial1_col1),
               $signed(actual_y[0][0]), $signed(actual_y[0][1]),
               $signed(actual_y[1][0]), $signed(actual_y[1][1]));
      $display("  Final exp={%0d,%0d} act={%0d,%0d}",
               $signed(final_col0), $signed(final_col1),
               $signed(get_acc_col(0)), $signed(get_acc_col(1)));
    end
  endtask

  task automatic test_n_tiling_case();
    logic [SIZE-1:0] done_seen;
    int fail_before;

    reset_dut();
    case_name = "n_tiling_2x2_x_2x4";
    case_act_rows = 2;
    num_tiles_i = TILE_COUNT_WIDTH'(2);

    act_matrix[0][0] = 8'sd1;
    act_matrix[0][1] = 8'sd2;
    act_matrix[1][0] = -8'sd3;
    act_matrix[1][1] = 8'sd4;

    $display("CASE 6: %s", case_name);
    fail_before = fail_count;

    set_weight_tile(8'sd5, -8'sd2, 8'sd7, 8'sd3);
    load_weights_and_switch(done_seen);
    expect_flag("tile 0 weight load reached bottom row", done_seen == 2'b11);
    clear_outputs();
    start_capture(2);
    stream_activation_matrix();
    observe_results();
    stop_capture();
    expect_psum_eq("tile0 Y[0][0]", actual_y[0][0], 18'sd19);
    expect_psum_eq("tile0 Y[0][1]", actual_y[0][1], 18'sd4);
    expect_psum_eq("tile0 Y[1][0]", actual_y[1][0], 18'sd13);
    expect_psum_eq("tile0 Y[1][1]", actual_y[1][1], 18'sd18);
    expect_acc_eq("tile0 acc col0", get_acc_col(0), 32'sd32);
    expect_acc_eq("tile0 acc col1", get_acc_col(1), 32'sd22);

    set_weight_tile(8'sd1, 8'sd6, -8'sd4, 8'sd2);
    load_weights_and_switch(done_seen);
    expect_flag("tile 1 weight load reached bottom row", done_seen == 2'b11);
    clear_outputs();
    start_capture(2);
    stream_activation_matrix();
    observe_results();
    stop_capture();
    expect_psum_eq("tile1 Y[0][0]", actual_y[0][0], -18'sd7);
    expect_psum_eq("tile1 Y[0][1]", actual_y[0][1], 18'sd10);
    expect_psum_eq("tile1 Y[1][0]", actual_y[1][0], -18'sd19);
    expect_psum_eq("tile1 Y[1][1]", actual_y[1][1], -18'sd10);
    expect_acc_eq("tile1 acc col0", get_acc_col(0), -32'sd26);
    expect_acc_eq("tile1 acc col1", get_acc_col(1), 32'sd0);
    expect_flag("overflow stayed clear", overflow_flatten_o == '0);

    if (fail_count == fail_before) begin
      $display("  PASS: %s", case_name);
    end else begin
      $display("  tile0 act={[%0d %0d] [%0d %0d]}",
               $signed(18'sd19), $signed(18'sd4),
               $signed(18'sd13), $signed(18'sd18));
      $display("  tile1 act={[%0d %0d] [%0d %0d]}",
               $signed(-18'sd7), $signed(18'sd10),
               $signed(-18'sd19), $signed(-18'sd10));
    end
  endtask

  task automatic test_padding_both_sides_case();
    logic [SIZE-1:0] done_seen;
    int fail_before;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial0_col0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial0_col1;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial1_col0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial1_col1;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial0_col2;
    logic signed [LOCAL_PSUM_WIDTH-1:0] partial1_col2;

    reset_dut();
    case_name = "padding_1x3_x_3x3";
    case_act_rows = 2;
    num_tiles_i = TILE_COUNT_WIDTH'(2);

    partial0_col0 = dot_product_2(8'sd2, -8'sd1, 8'sd5, 8'sd7);
    partial0_col1 = dot_product_2(8'sd2, -8'sd1, -8'sd2, 8'sd3);
    partial1_col0 = dot_product_2(8'sd3, 8'sd0, -8'sd6, 8'sd0);
    partial1_col1 = dot_product_2(8'sd3, 8'sd0, 8'sd2, 8'sd0);
    partial0_col2 = dot_product_2(8'sd2, -8'sd1, 8'sd4, -8'sd1);
    partial1_col2 = dot_product_2(8'sd3, 8'sd0, 8'sd8, 8'sd0);

    $display("CASE 7: %s exp_acc={%0d,%0d,%0d}",
             case_name,
             $signed(partial0_col0 + partial1_col0),
             $signed(partial0_col1 + partial1_col1),
             $signed(partial0_col2 + partial1_col2));
    fail_before = fail_count;

    set_weight_tile(8'sd5, -8'sd2, 8'sd7, 8'sd3);
    load_weights_and_switch(done_seen);
    expect_flag("tile 0.0 weight load reached bottom row", done_seen == 2'b11);
    clear_outputs();
    start_capture(2);
    stream_one_pair(8'sd2, -8'sd1, 1'b1);
    set_weight_tile(-8'sd6, 8'sd2, 8'sd0, 8'sd0);
    load_weights_and_switch(done_seen);
    expect_flag("tile 0.1 weight load reached bottom row", done_seen == 2'b11);
    stream_one_pair(8'sd3, 8'sd0, 1'b0);
    observe_results();
    stop_capture();
    expect_psum_eq("tile0 partial[0][0]", actual_y[0][0], partial0_col0);
    expect_psum_eq("tile0 partial[0][1]", actual_y[0][1], partial0_col1);
    expect_psum_eq("tile0 partial[1][0]", actual_y[1][0], partial1_col0);
    expect_psum_eq("tile0 partial[1][1]", actual_y[1][1], partial1_col1);
    expect_acc_eq("tile0 final col0", get_acc_col(0), partial0_col0 + partial1_col0);
    expect_acc_eq("tile0 final col1", get_acc_col(1), partial0_col1 + partial1_col1);

    set_weight_tile(8'sd4, 8'sd0, -8'sd1, 8'sd0);
    load_weights_and_switch(done_seen);
    expect_flag("tile 1.0 weight load reached bottom row", done_seen == 2'b11);
    clear_outputs();
    start_capture(2);
    stream_one_pair(8'sd2, -8'sd1, 1'b1);
    set_weight_tile(8'sd8, 8'sd0, 8'sd0, 8'sd0);
    load_weights_and_switch(done_seen);
    expect_flag("tile 1.1 weight load reached bottom row", done_seen == 2'b11);
    stream_one_pair(8'sd3, 8'sd0, 1'b0);
    observe_results();
    stop_capture();
    expect_psum_eq("tile1 partial[0][0]", actual_y[0][0], partial0_col2);
    expect_psum_eq("tile1 partial[0][1]", actual_y[0][1], 18'sd0);
    expect_psum_eq("tile1 partial[1][0]", actual_y[1][0], partial1_col2);
    expect_psum_eq("tile1 partial[1][1]", actual_y[1][1], 18'sd0);
    expect_acc_eq("tile1 final col2", get_acc_col(0), partial0_col2 + partial1_col2);
    expect_acc_eq("tile1 padded col", get_acc_col(1), 32'sd0);
    expect_flag("overflow stayed clear", overflow_flatten_o == '0);

    if (fail_count == fail_before) begin
      $display("  PASS: %s", case_name);
    end else begin
      $display("  Final exp={%0d,%0d,%0d} act={%0d,%0d,%0d}",
               $signed(partial0_col0 + partial1_col0),
               $signed(partial0_col1 + partial1_col1),
               $signed(partial0_col2 + partial1_col2),
               $signed(partial0_col0 + partial1_col0),
               $signed(partial0_col1 + partial1_col1),
               $signed(get_acc_col(0)));
    end
  endtask

  initial begin
    init_signals();
    print_header("TEST: SA 2x2 COMPUTATION");

    for (int case_id = 0; case_id < NUM_CASES; case_id++) begin
      run_case(case_id);
    end
    test_k_tiling_case();
    test_n_tiling_case();
    test_padding_both_sides_case();

    print_header("SUMMARY");
    $display("Total checks : %0d", test_count);
    $display("Pass count   : %0d", pass_count);
    $display("Fail count   : %0d", fail_count);

    if (fail_count != 0) begin
      $fatal(1, "test_sa_2x2_computation failed");
    end

    $display("All computation checks passed.");
    $finish;
  end

endmodule
