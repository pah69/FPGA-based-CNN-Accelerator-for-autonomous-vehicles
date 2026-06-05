`timescale 1ns / 1ps

module test_weight_double_buffer;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = SIZE;
  localparam int ACC_WIDTH = 32;
  localparam int CLK_PERIOD = 10;
  localparam bit ENABLE_TRACE = 1'b1;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;

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

  logic signed [DATA_WIDTH-1:0] initial_weights [0:SIZE-1][0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] buffered_weights[0:SIZE-1][0:SIZE-1];

  int cycle_count;
  int test_count;
  int pass_count;
  int fail_count;

  systolic_array #(
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
    $dumpfile("ws_sa_2x2_tb.vcd");
    $dumpvars(0, ws_sa_2x2_tb);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end

  function automatic logic signed [(DATA_WIDTH*SIZE)-1:0] pack_data_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    pack_data_pair = {lane1, lane0};
  endfunction

  task automatic print_header(input string title);
    $display("");
    $display("============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

  task automatic display_weight_state(input string tag);
    if (!ENABLE_TRACE) begin
      return;
    end

    $display("[%0t][cycle %0d] %s", $time, cycle_count, tag);
    $display("  inputs : load=%b switch=%b wgt_in={%0d,%0d} done=%b",
             wgt_load_i,
             weight_switch_i,
             $signed(wgt_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH]),
             $signed(wgt_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH]),
             wgt_load_done_o);
    $display("  active : {%0d,%0d;%0d,%0d}",
             $signed(dut.pe_0_0.weight_active),
             $signed(dut.pe_0_1.weight_active),
             $signed(dut.pe_1_0.weight_active),
             $signed(dut.pe_1_1.weight_active));
    $display("  shadow : {%0d,%0d;%0d,%0d}",
             $signed(dut.pe_0_0.weight_shadow),
             $signed(dut.pe_0_1.weight_shadow),
             $signed(dut.pe_1_0.weight_shadow),
             $signed(dut.pe_1_1.weight_shadow));
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

  task automatic expect_data_eq(
      input string label,
      input logic signed [DATA_WIDTH-1:0] actual,
      input logic signed [DATA_WIDTH-1:0] expected
  );
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

    cycle_count = 0;
    test_count  = 0;
    pass_count  = 0;
    fail_count  = 0;
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

    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    display_weight_state("after reset");
  endtask

  task automatic configure_weight_sets();
    // Distinct weights to verify the normal top-row / bottom-row placement.
    initial_weights[0][0] = 8'sd5;
    initial_weights[0][1] = -8'sd2;
    initial_weights[1][0] = 8'sd7;
    initial_weights[1][1] = 8'sd3;

    // Use the same value in both rows for the second preload so we can focus
    // purely on shadow-vs-active behavior without a row-order race.
    buffered_weights[0][0] = 8'sd11;
    buffered_weights[0][1] = -8'sd6;
    buffered_weights[1][0] = 8'sd11;
    buffered_weights[1][1] = -8'sd6;
  endtask

  task automatic drive_weight_cycle(
      input logic signed [(DATA_WIDTH*SIZE)-1:0] next_wgt_flatten,
      input logic [SIZE-1:0] next_wgt_load,
      input logic next_weight_switch,
      input string tag
  );
    @(negedge clk);
    wgt_flatten_i   = next_wgt_flatten;
    wgt_load_i      = next_wgt_load;
    weight_switch_i = next_weight_switch;
    work_i          = 1'b0;
    act_flatten_i   = '0;
    act_valid_i     = '0;

    @(posedge clk);
    display_weight_state(tag);
  endtask

  task automatic expect_active_initial_weights();
    expect_data_eq("active pe_0_0", dut.pe_0_0.weight_active, initial_weights[0][0]);
    expect_data_eq("active pe_0_1", dut.pe_0_1.weight_active, initial_weights[0][1]);
    expect_data_eq("active pe_1_0", dut.pe_1_0.weight_active, initial_weights[1][0]);
    expect_data_eq("active pe_1_1", dut.pe_1_1.weight_active, initial_weights[1][1]);
  endtask

  task automatic expect_shadow_buffered_weights();
    expect_data_eq("shadow pe_0_0", dut.pe_0_0.weight_shadow, buffered_weights[0][0]);
    expect_data_eq("shadow pe_0_1", dut.pe_0_1.weight_shadow, buffered_weights[0][1]);
    expect_data_eq("shadow pe_1_0", dut.pe_1_0.weight_shadow, buffered_weights[1][0]);
    expect_data_eq("shadow pe_1_1", dut.pe_1_1.weight_shadow, buffered_weights[1][1]);
  endtask

  task automatic expect_active_buffered_weights();
    expect_data_eq("active pe_0_0 after switch", dut.pe_0_0.weight_active, buffered_weights[0][0]);
    expect_data_eq("active pe_0_1 after switch", dut.pe_0_1.weight_active, buffered_weights[0][1]);
    expect_data_eq("active pe_1_0 after switch", dut.pe_1_0.weight_active, buffered_weights[1][0]);
    expect_data_eq("active pe_1_1 after switch", dut.pe_1_1.weight_active, buffered_weights[1][1]);
  endtask

  task automatic load_initial_weights_and_switch(output logic [SIZE-1:0] done_seen);
    done_seen = '0;

    drive_weight_cycle(
        pack_data_pair(initial_weights[1][0], initial_weights[1][1]),
        2'b11,
        1'b0,
        "load initial bottom row"
    );
    done_seen |= wgt_load_done_o;

    drive_weight_cycle(
        pack_data_pair(initial_weights[0][0], initial_weights[0][1]),
        2'b11,
        1'b0,
        "load initial top row"
    );
    done_seen |= wgt_load_done_o;

    drive_weight_cycle('0, '0, 1'b1, "switch initial weights");
    done_seen |= wgt_load_done_o;

    drive_weight_cycle('0, '0, 1'b0, "initial weights active");
    done_seen |= wgt_load_done_o;
  endtask

  task automatic preload_next_weights_without_switch();
    drive_weight_cycle(
        pack_data_pair(buffered_weights[1][0], buffered_weights[1][1]),
        2'b11,
        1'b0,
        "preload buffered row 1"
    );

    drive_weight_cycle(
        pack_data_pair(buffered_weights[0][0], buffered_weights[0][1]),
        2'b11,
        1'b0,
        "preload buffered row 0"
    );

    drive_weight_cycle('0, '0, 1'b0, "buffered weights settled in shadow");
  endtask

  task automatic switch_to_buffered_weights();
    drive_weight_cycle('0, '0, 1'b1, "switch buffered weights active");
    drive_weight_cycle('0, '0, 1'b0, "buffered weights active");
  endtask

  task automatic test_pe_double_buffer_only();
    logic [SIZE-1:0] done_seen;

    print_header("TEST: systolic_array PE DOUBLE BUFFER ONLY");
    reset_dut();
    configure_weight_sets();

    // Phase 1: normal array load + switch into the first active weight set.
    load_initial_weights_and_switch(done_seen);
    expect_flag("initial load reached bottom row", done_seen == 2'b11);
    expect_active_initial_weights();

    // Phase 2: preload the next weights into shadow only.
    preload_next_weights_without_switch();
    expect_active_initial_weights();
    expect_shadow_buffered_weights();

    // Phase 3: one global switch should commit the new buffered weights.
    switch_to_buffered_weights();
    expect_active_buffered_weights();
    expect_flag("no overflow during weight-only test", overflow_flatten_o == '0);
    expect_flag("no psum valid during weight-only test", psum_valid_o == '0);
  endtask

  initial begin
    init_signals();
    test_pe_double_buffer_only();

    print_header("SUMMARY");
    $display("Total checks : %0d", test_count);
    $display("Pass count   : %0d", pass_count);
    $display("Fail count   : %0d", fail_count);

    if (fail_count != 0) begin
      $fatal(1, "ws_sa_2x2_tb failed");
    end

    $display("All double-buffer checks passed.");
    $finish;
  end

endmodule
