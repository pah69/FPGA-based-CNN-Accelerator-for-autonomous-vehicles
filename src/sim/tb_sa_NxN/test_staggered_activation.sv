`timescale 1ns / 1ps

module test_staggered_activation;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = SIZE;
  localparam int ACC_WIDTH = 32;
  localparam int CLK_PERIOD = 10;
  localparam int ACT_STAGGER_CYCLES = 4;
  localparam bit ENABLE_TRACE = 1'b1;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;

  logic                                      clk;
  logic                                      rst_n;
  logic                                      work_i;
  logic        [        TILE_COUNT_WIDTH-1:0] num_tiles_i;

  logic signed [      (DATA_WIDTH*SIZE)-1:0] wgt_flatten_i;
  logic        [                   SIZE-1:0] wgt_load_i;
  logic                                      weight_switch_i;

  logic signed [      (DATA_WIDTH*SIZE)-1:0] act_flatten_i;
  logic        [                   SIZE-1:0] act_valid_i;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o;
  logic        [                   SIZE-1:0] psum_valid_o;
  logic signed [       (ACC_WIDTH*SIZE)-1:0] result_flatten_o;
  logic                                      done_o;
  logic        [                   SIZE-1:0] wgt_load_done_o;

  logic                                      overflow_clr_i;
  logic        [              SIZE*SIZE-1:0] overflow_flatten_o;

  logic signed [             DATA_WIDTH-1:0] weight_matrix        [0:SIZE-1][0:SIZE-1];
  logic signed [             DATA_WIDTH-1:0] row0_act;
  logic signed [             DATA_WIDTH-1:0] row1_act;

  logic signed [       LOCAL_PSUM_WIDTH-1:0] expected_top_col0;
  logic signed [       LOCAL_PSUM_WIDTH-1:0] expected_top_col1;
  logic signed [       LOCAL_PSUM_WIDTH-1:0] expected_bottom_col0;
  logic signed [       LOCAL_PSUM_WIDTH-1:0] expected_bottom_col1;

  int                                        cycle_count;
  int                                        test_count;
  int                                        pass_count;
  int                                        fail_count;

  ws_sa_2x2 #(
      .SIZE(SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .NUM_TILES(NUM_TILES),
      .ACC_WIDTH(ACC_WIDTH),
      .TILE_COUNT_WIDTH(TILE_COUNT_WIDTH),
      .ENABLE_LOCAL_ACCUM(1'b0)
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
    $dumpfile("test_staggered_activation.vcd");
    $dumpvars(0, test_staggered_activation);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_data_pair(
      input logic signed [DATA_WIDTH-1:0] lane0, input logic signed [DATA_WIDTH-1:0] lane1);
    pack_data_pair = {lane1, lane0};
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_psum_col(input int col);
    case (col)
      0: get_psum_col = psum_flatten_o[(0*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
      default: get_psum_col = psum_flatten_o[(1*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
    endcase
  endfunction

  task automatic print_header(input string title);
    $display("");
    $display("============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

  task automatic display_activation_state(input string tag);
    if (!ENABLE_TRACE) begin
      return;
    end

    $display("[%0t][cycle %0d] %s", $time, cycle_count, tag);
    $display("  act_in : valid=%b data={%0d,%0d}", act_valid_i,
             $signed(act_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH]),
             $signed(act_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH]));
    $display("  p00->p01 : act_v=%b act=%0d", dut.act_v_0_0_to_0_1, $signed(dut.act_0_0_to_0_1));
    $display("  p00->p10 : psum_v=%b psum=%0d", dut.psum_v_0_0_to_1_0, $signed(
                                                                           dut.psum_0_0_to_1_0));
    $display("  p10->p11 : act_v=%b act=%0d", dut.act_v_1_0_to_1_1, $signed(dut.act_1_0_to_1_1));
    $display("  p01->p11 : psum_v=%b psum=%0d", dut.psum_v_0_1_to_1_1, $signed(
                                                                           dut.psum_0_1_to_1_1));
    $display("  bottom   : valid=%b psum={%0d,%0d}", psum_valid_o, $signed(get_psum_col(0)),
             $signed(get_psum_col(1)));
  endtask

  task automatic expect_flag(input string label, input logic condition);
    test_count++;
    if (condition) begin
      pass_count++;
      $display("  PASS: %s", label);
    end else begin
      fail_count++;
      $display("  FAIL: %s", label);
    end
  endtask

  task automatic expect_data_eq(input string label, input logic signed [DATA_WIDTH-1:0] actual,
                                input logic signed [DATA_WIDTH-1:0] expected);
    test_count++;
    if (actual === expected) begin
      pass_count++;
      $display("  PASS: %s -> %0d", label, $signed(actual));
    end else begin
      fail_count++;
      $display("  FAIL: %s -> got %0d expected %0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic expect_psum_eq(input string label,
                                input logic signed [LOCAL_PSUM_WIDTH-1:0] actual,
                                input logic signed [LOCAL_PSUM_WIDTH-1:0] expected);
    test_count++;
    if (actual === expected) begin
      pass_count++;
      $display("  PASS: %s -> %0d", label, $signed(actual));
    end else begin
      fail_count++;
      $display("  FAIL: %s -> got %0d expected %0d", label, $signed(actual), $signed(expected));
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

    cycle_count     = 0;
    test_count      = 0;
    pass_count      = 0;
    fail_count      = 0;
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

    rst_n           = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    display_activation_state("after reset");
  endtask

  task automatic configure_test_data();
    weight_matrix[0][0] = 8'sd2;
    weight_matrix[0][1] = 8'sd3;
    weight_matrix[1][0] = 8'sd5;
    weight_matrix[1][1] = 8'sd7;

    row0_act = 8'sd4;
    row1_act = 8'sd6;

    expected_top_col0 = row0_act * weight_matrix[0][0];
    expected_top_col1 = row0_act * weight_matrix[0][1];
    expected_bottom_col0 = expected_top_col0 + (row1_act * weight_matrix[1][0]);
    expected_bottom_col1 = expected_top_col1 + (row1_act * weight_matrix[1][1]);
  endtask

  task automatic drive_weight_cycle(input logic signed [(DATA_WIDTH*SIZE)-1:0] next_wgt_flatten,
                                    input logic [SIZE-1:0] next_wgt_load,
                                    input logic next_weight_switch, input string tag);
    @(negedge clk);
    wgt_flatten_i   = next_wgt_flatten;
    wgt_load_i      = next_wgt_load;
    weight_switch_i = next_weight_switch;
    act_flatten_i   = '0;
    act_valid_i     = '0;
    work_i          = 1'b0;

    @(posedge clk);
    display_activation_state(tag);
  endtask

  task automatic drive_activation_cycle(input logic signed [(DATA_WIDTH*SIZE)-1:0] next_act_flatten,
                                        input logic [SIZE-1:0] next_act_valid, input string tag);
    @(negedge clk);
    act_flatten_i   = next_act_flatten;
    act_valid_i     = next_act_valid;
    wgt_flatten_i   = '0;
    wgt_load_i      = '0;
    weight_switch_i = 1'b0;
    work_i          = 1'b0;

    @(posedge clk);
    display_activation_state(tag);
  endtask

  task automatic load_weights_and_switch(output logic [SIZE-1:0] done_seen);
    done_seen = '0;

    drive_weight_cycle(pack_data_pair(weight_matrix[1][0], weight_matrix[1][1]), 2'b11, 1'b0,
                       "load weight row 1");
    done_seen |= wgt_load_done_o;

    drive_weight_cycle(pack_data_pair(weight_matrix[0][0], weight_matrix[0][1]), 2'b11, 1'b0,
                       "load weight row 0");
    done_seen |= wgt_load_done_o;

    drive_weight_cycle('0, '0, 1'b1, "switch weights active");
    done_seen |= wgt_load_done_o;

    drive_weight_cycle('0, '0, 1'b0, "weights active");
    done_seen |= wgt_load_done_o;
  endtask

  task automatic drive_staggered_activation_pair();
    drive_activation_cycle(pack_data_pair(row0_act, '0), 2'b01, "drive row0 activation");

    repeat (ACT_STAGGER_CYCLES - 1) begin
      drive_activation_cycle('0, '0, "stagger bubble");
      expect_flag("row0 not yet visible at pe10 during bubble", !dut.psum_v_0_0_to_1_0);
    end

    drive_activation_cycle(pack_data_pair('0, row1_act), 2'b10, "drive row1 activation");
    expect_flag("row0 forwarded to pe01 on row1 cycle", dut.act_v_0_0_to_0_1);
    expect_data_eq("row0 value at pe01", dut.act_0_0_to_0_1, row0_act);
    expect_flag("pe10 sees aligned act and psum", dut.psum_v_0_0_to_1_0 && dut.pe_1_0.act_valid_i);
    expect_psum_eq("aligned psum into pe10", dut.psum_0_0_to_1_0, expected_top_col0);
    expect_data_eq("aligned act into pe10", dut.pe_1_0.act_i, row1_act);

    drive_activation_cycle('0, '0, "clear activation inputs");
  endtask

  task automatic observe_stagger_results();
    logic found_pe11_alignment;
    logic got_col0;
    logic got_col1;
    logic signed [DATA_WIDTH-1:0] captured_pe11_act;
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_pe11_psum;
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_col0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_col1;

    found_pe11_alignment = 1'b0;
    got_col0 = 1'b0;
    got_col1 = 1'b0;
    captured_pe11_act = '0;
    captured_pe11_psum = '0;
    captured_col0 = '0;
    captured_col1 = '0;

    for (int cycle = 0; cycle < 16; cycle++) begin
      @(posedge clk);
      display_activation_state("observe stagger results");

      if (!found_pe11_alignment && dut.psum_v_0_1_to_1_1 && dut.act_v_1_0_to_1_1) begin
        found_pe11_alignment = 1'b1;
        captured_pe11_act = dut.act_1_0_to_1_1;
        captured_pe11_psum = dut.psum_0_1_to_1_1;
      end

      if (!got_col0 && psum_valid_o[0]) begin
        got_col0 = 1'b1;
        captured_col0 = get_psum_col(0);
      end

      if (!got_col1 && psum_valid_o[1]) begin
        got_col1 = 1'b1;
        captured_col1 = get_psum_col(1);
      end
    end

    expect_flag("pe11 alignment observed", found_pe11_alignment);
    if (found_pe11_alignment) begin
      expect_data_eq("aligned act into pe11", captured_pe11_act, row1_act);
      expect_psum_eq("aligned psum into pe11", captured_pe11_psum, expected_top_col1);
    end

    expect_flag("bottom output col0 observed", got_col0);
    expect_flag("bottom output col1 observed", got_col1);
    if (got_col0) begin
      expect_psum_eq("bottom output col0 value", captured_col0, expected_bottom_col0);
    end
    if (got_col1) begin
      expect_psum_eq("bottom output col1 value", captured_col1, expected_bottom_col1);
    end
  endtask

  task automatic test_staggered_activation_load();
    logic [SIZE-1:0] done_seen;

    print_header("TEST: STAGGERED ACTIVATION LOAD");
    reset_dut();
    configure_test_data();
    load_weights_and_switch(done_seen);

    expect_flag("weights reached bottom row before activation test", done_seen == 2'b11);

    drive_staggered_activation_pair();
    observe_stagger_results();

    expect_flag("no overflow during stagger test", overflow_flatten_o == '0);
  endtask

  initial begin
    init_signals();
    test_staggered_activation_load();

    print_header("SUMMARY");
    $display("Total checks : %0d", test_count);
    $display("Pass count   : %0d", pass_count);
    $display("Fail count   : %0d", fail_count);

    if (fail_count != 0) begin
      $fatal(1, "test_staggered_activation failed");
    end

    $display("All staggered activation checks passed.");
    $finish;
  end

endmodule
