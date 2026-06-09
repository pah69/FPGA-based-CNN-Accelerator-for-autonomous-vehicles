`timescale 1ns / 1ps

module test_activation_skew_ws_sa;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ROW_STAGGER_CYCLES = 4;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = 1;
  localparam int ACC_WIDTH = 32;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;
  localparam int CLK_PERIOD = 10;
  localparam int ROW1_VISIBLE_AFTER_EDGES =
      (ROW_STAGGER_CYCLES > 0) ? (ROW_STAGGER_CYCLES - 1) : 0;
  localparam int MAX_OBSERVE_CYCLES = 80;
  localparam bit ENABLE_TRACE = 1'b0;

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

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o;
  logic        [SIZE-1:0]                    psum_valid_o;
  logic signed [(ACC_WIDTH*SIZE)-1:0]        result_flatten_o;
  logic                                      done_o;
  logic        [SIZE-1:0]                    wgt_load_done_o;

  logic                 overflow_clr_i;
  logic [SIZE*SIZE-1:0] overflow_flatten_o;

  int test_count;
  int pass_count;
  int fail_count;

  logic signed [LOCAL_PSUM_WIDTH-1:0] captured_psum[0:SIZE-1];
  logic                               captured_valid[0:SIZE-1];
  logic signed [ACC_WIDTH-1:0]        captured_result[0:SIZE-1];
  logic                               done_seen;

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
      .ENABLE_LOCAL_ACCUM(1'b1),
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
      .psum_flatten_o    (psum_flatten_o),
      .psum_valid_o      (psum_valid_o),
      .result_flatten_o  (result_flatten_o),
      .done_o            (done_o),
      .wgt_load_done_o   (wgt_load_done_o),
      .overflow_clr_i    (overflow_clr_i),
      .overflow_flatten_o(overflow_flatten_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    pack_pair = {lane1, lane0};
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] get_skewed(input int lane);
    get_skewed = act_skewed_o[(lane*DATA_WIDTH)+:DATA_WIDTH];
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] get_raw(input int lane);
    get_raw = act_flat_raw_i[(lane*DATA_WIDTH)+:DATA_WIDTH];
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_psum(input int col);
    get_psum = psum_flatten_o[(col*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] get_result(input int col);
    get_result = result_flatten_o[(col*ACC_WIDTH)+:ACC_WIDTH];
  endfunction

  task automatic expect_flag(input string label, input logic condition);
    test_count++;
    if (condition) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s", label);
      display_skew_state("failure context");
    end
  endtask

  task automatic expect_data_eq(
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
      display_skew_state("failure context");
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
      display_sa_state("psum failure context");
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
      display_sa_state("accumulator failure context");
    end
  endtask

  task automatic print_header(input string title);
    $display("");
    $display("============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

  task automatic display_skew_state(input string tag);
    if (!ENABLE_TRACE) begin
      return;
    end

    $display("[%0t] %s", $time, tag);
    $display("  raw   : valid=%b data={row1:%0d,row0:%0d}",
             act_valid_raw_i, $signed(get_raw(1)), $signed(get_raw(0)));
    $display("  skewed: valid=%b data={row1:%0d,row0:%0d}",
             act_valid_skewed_o, $signed(get_skewed(1)), $signed(get_skewed(0)));
    $display("  pipe  : row1 valid_pipe={%0b,%0b,%0b,%0b} data_pipe={%0d,%0d,%0d,%0d}",
             u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.valid_pipe[3],
             u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.valid_pipe[2],
             u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.valid_pipe[1],
             u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.valid_pipe[0],
             $signed(u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.data_pipe[3]),
             $signed(u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.data_pipe[2]),
             $signed(u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.data_pipe[1]),
             $signed(u_skew_buffer.GEN_ROW_SKEW[1].GEN_DELAY.data_pipe[0]));
  endtask

  task automatic display_sa_state(input string tag);
    if (!ENABLE_TRACE) begin
      return;
    end

    $display("[%0t] %s", $time, tag);
    $display("  SA input : act_valid=%b act={row1:%0d,row0:%0d}",
             act_valid_skewed_o, $signed(get_skewed(1)), $signed(get_skewed(0)));
    $display("  PE align : p00_psum_v=%b p00_psum=%0d pe10_act_v=%b pe10_act=%0d",
             u_systolic_array.psum_v_0_0_to_1_0,
             $signed(u_systolic_array.psum_0_0_to_1_0),
             u_systolic_array.pe_1_0.act_valid_i,
             $signed(u_systolic_array.pe_1_0.act_i));
    $display("  PE align : p01_psum_v=%b p01_psum=%0d pe11_act_v=%b pe11_act=%0d",
             u_systolic_array.psum_v_0_1_to_1_1,
             $signed(u_systolic_array.psum_0_1_to_1_1),
             u_systolic_array.pe_1_1.act_valid_i,
             $signed(u_systolic_array.pe_1_1.act_i));
    $display("  outputs  : psum_valid=%b psum={col1:%0d,col0:%0d} done=%b result={col1:%0d,col0:%0d}",
             psum_valid_o, $signed(get_psum(1)), $signed(get_psum(0)), done_o,
             $signed(get_result(1)), $signed(get_result(0)));
  endtask

  task automatic init_signals();
    rst_n             = 1'b0;
    work_i            = 1'b0;
    num_tiles_i       = TILE_COUNT_WIDTH'(NUM_TILES);
    act_flat_raw_i    = '0;
    act_valid_raw_i   = '0;
    wgt_flatten_i     = '0;
    wgt_load_i        = '0;
    weight_switch_i   = 1'b0;
    overflow_clr_i    = 1'b0;
    test_count        = 0;
    pass_count        = 0;
    fail_count        = 0;
    done_seen         = 1'b0;

    for (int col = 0; col < SIZE; col++) begin
      captured_psum[col]   = '0;
      captured_valid[col]  = 1'b0;
      captured_result[col] = '0;
    end
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
    wgt_flatten_i   = pack_pair(lane0, lane1);
    wgt_load_i      = load_mask;
    weight_switch_i = switch_weights;
    act_flat_raw_i  = '0;
    act_valid_raw_i = '0;
    work_i          = 1'b0;
    @(posedge clk);
    #1;
  endtask

  task automatic load_direct_weights();
    logic [SIZE-1:0] done_seen_local;

    done_seen_local = '0;

    drive_weight_cycle(8'sd5, 8'sd7, 2'b11, 1'b0);
    done_seen_local |= wgt_load_done_o;

    drive_weight_cycle(8'sd2, 8'sd3, 2'b11, 1'b0);
    done_seen_local |= wgt_load_done_o;

    drive_weight_cycle('0, '0, '0, 1'b1);
    done_seen_local |= wgt_load_done_o;

    drive_weight_cycle('0, '0, '0, 1'b0);
    done_seen_local |= wgt_load_done_o;

    expect_flag("direct weight load reached bottom row", done_seen_local == 2'b11);
  endtask

  task automatic stream_raw_activation_and_check_skew(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    print_header("TEST: DIRECT ACTIVATION SKEW TIMING");

    @(negedge clk);
    act_flat_raw_i  = pack_pair(lane0, lane1);
    act_valid_raw_i = 2'b11;
    work_i          = 1'b1;
    @(posedge clk);
    #1;
    display_skew_state("launch raw activations");

    expect_flag("row 0 valid is immediate", act_valid_skewed_o[0] == 1'b1);
    expect_data_eq("row 0 data is immediate", get_skewed(0), lane0);
    expect_flag("row 1 is not valid on row 0 cycle", act_valid_skewed_o[1] == 1'b0);

    @(negedge clk);
    act_flat_raw_i  = '0;
    act_valid_raw_i = '0;
    work_i          = 1'b0;

    for (int delay_cycle = 1; delay_cycle < ROW1_VISIBLE_AFTER_EDGES; delay_cycle++) begin
      @(posedge clk);
      #1;
      display_skew_state($sformatf("row 1 delay pipe cycle %0d", delay_cycle));
      expect_flag($sformatf("row 1 still delayed at cycle %0d", delay_cycle),
                  act_valid_skewed_o[1] == 1'b0);
    end

    @(posedge clk);
    #1;
    display_skew_state($sformatf("row 1 visible at cycle %0d", ROW1_VISIBLE_AFTER_EDGES));
    expect_flag("row 1 valid after configured stagger pipeline", act_valid_skewed_o[1] == 1'b1);
    expect_data_eq("row 1 data after configured stagger pipeline", get_skewed(1), lane1);
  endtask

  task automatic observe_outputs();
    print_header("TEST: COMPUTATION AFTER STAGGERED ACTIVATION LOAD");

    for (int cycle = 0; cycle < MAX_OBSERVE_CYCLES; cycle++) begin
      @(posedge clk);
      #1;
      display_sa_state($sformatf("compute observe cycle %0d", cycle));

      for (int col = 0; col < SIZE; col++) begin
        if (psum_valid_o[col] && !captured_valid[col]) begin
          captured_valid[col] = 1'b1;
          captured_psum[col]  = get_psum(col);
          $display("  CAPTURE: psum col%0d = %0d", col, $signed(get_psum(col)));
        end
      end

      if (done_o && !done_seen) begin
        done_seen = 1'b1;
        for (int col = 0; col < SIZE; col++) begin
          captured_result[col] = get_result(col);
        end
        $display("  CAPTURE: accumulator done result={col1:%0d,col0:%0d}",
                 $signed(get_result(1)), $signed(get_result(0)));
      end

      if (captured_valid[0] && captured_valid[1] && done_seen) begin
        $display("  INFO: observed both output columns and accumulator done by cycle %0d", cycle);
        break;
      end
    end
  endtask

  task automatic check_computation_after_stagger();
    logic signed [LOCAL_PSUM_WIDTH-1:0] expected_col0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] expected_col1;

    // Weights loaded in load_direct_weights:
    //   W = [[2, 3],
    //        [5, 7]]
    // Activation vector loaded in stream_raw_activation_and_check_skew:
    //   A = [4, 6]
    expected_col0 = (8'sd4 * 8'sd2) + (8'sd6 * 8'sd5);
    expected_col1 = (8'sd4 * 8'sd3) + (8'sd6 * 8'sd7);

    observe_outputs();

    expect_flag("column 0 produced a psum after stagger", captured_valid[0]);
    expect_flag("column 1 produced a psum after stagger", captured_valid[1]);
    expect_psum_eq("column 0 skewed weighted sum", captured_psum[0], expected_col0);
    expect_psum_eq("column 1 skewed weighted sum", captured_psum[1], expected_col1);
    expect_flag("local output accumulators asserted done after stagger", done_seen);
    expect_acc_eq("accumulator result column 0", captured_result[0], expected_col0);
    expect_acc_eq("accumulator result column 1", captured_result[1], expected_col1);
    expect_flag("no PE overflow while testing activation skew computation",
                overflow_flatten_o == '0);
  endtask

  initial begin
    init_signals();
    reset_dut();
    load_direct_weights();

    stream_raw_activation_and_check_skew(8'sd4, 8'sd6);
    check_computation_after_stagger();

    $display("test_activation_skew_ws_sa: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_activation_skew_ws_sa failed");
    end
    $finish;
  end

endmodule : test_activation_skew_ws_sa
