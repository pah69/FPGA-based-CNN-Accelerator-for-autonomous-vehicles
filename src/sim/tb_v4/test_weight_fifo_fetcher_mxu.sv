`timescale 1ns / 1ps

module test_weight_fifo_fetcher_mxu;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = 1;
  localparam int ACC_WIDTH = 32;
  localparam int WGT_FIFO_DEPTH = 4;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;
  localparam int CLK_PERIOD = 10;

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

  mxu #(
      .SIZE              (SIZE),
      .DATA_WIDTH        (DATA_WIDTH),
      .LOCAL_PSUM_WIDTH  (LOCAL_PSUM_WIDTH),
      .NUM_TILES         (NUM_TILES),
      .ACC_WIDTH         (ACC_WIDTH),
      .ENABLE_LOCAL_ACCUM(1'b1),
      .WGT_FIFO_DEPTH    (WGT_FIFO_DEPTH),
      .TILE_COUNT_WIDTH  (TILE_COUNT_WIDTH)
  ) dut (
      .clk                (clk),
      .rst_n              (rst_n),
      .work_i             (work_i),
      .num_tiles_i        (num_tiles_i),
      .start_wgt_load_i   (start_wgt_load_i),
      .wgt_fetcher_ready_o(wgt_fetcher_ready_o),
      .wgt_fifo_wdata_i   (wgt_fifo_wdata_i),
      .wgt_fifo_wr_en_i   (wgt_fifo_wr_en_i),
      .wgt_fifo_full_o    (wgt_fifo_full_o),
      .wgt_fifo_empty_o   (wgt_fifo_empty_o),
      .act_flat_raw_i     (act_flat_raw_i),
      .act_valid_raw_i    (act_valid_raw_i),
      .psum_flatten_o     (psum_flatten_o),
      .psum_valid_o       (psum_valid_o),
      .result_flatten_o   (result_flatten_o),
      .done_o             (done_o),
      .wgt_load_done_o    (wgt_load_done_o),
      .overflow_clr_i     (overflow_clr_i),
      .overflow_flatten_o (overflow_flatten_o)
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

  task automatic init_signals();
    rst_n              = 1'b0;
    work_i             = 1'b0;
    num_tiles_i        = TILE_COUNT_WIDTH'(NUM_TILES);
    start_wgt_load_i   = 1'b0;
    wgt_fifo_wdata_i   = '0;
    wgt_fifo_wr_en_i   = 1'b0;
    act_flat_raw_i     = '0;
    act_valid_raw_i    = '0;
    overflow_clr_i     = 1'b0;
    test_count         = 0;
    pass_count         = 0;
    fail_count         = 0;
    done_seen          = 1'b0;

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

  task automatic fifo_write_row(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    @(negedge clk);
    wgt_fifo_wdata_i = pack_pair(lane0, lane1);
    wgt_fifo_wr_en_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    wgt_fifo_wr_en_i = 1'b0;
    wgt_fifo_wdata_i = '0;
  endtask

  task automatic pulse_start_load();
    @(negedge clk);
    start_wgt_load_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    start_wgt_load_i = 1'b0;
  endtask

  task automatic load_weights_from_fifo();
    logic [SIZE-1:0] done_seen_local;

    done_seen_local = '0;

    fifo_write_row(8'sd7, 8'sd3);
    expect_flag("fetcher waits until a full 2-row weight tile is stored",
                wgt_fetcher_ready_o == 1'b0);

    pulse_start_load();
    repeat (2) begin
      @(posedge clk);
      #1;
      done_seen_local |= wgt_load_done_o;
    end
    expect_flag("early start with one FIFO row does not load array", done_seen_local == '0);

    fifo_write_row(8'sd5, -8'sd2);
    expect_flag("fetcher ready after bottom and top rows are stored",
                wgt_fetcher_ready_o == 1'b1);

    pulse_start_load();
    repeat (12) begin
      @(posedge clk);
      #1;
      done_seen_local |= wgt_load_done_o;
    end

    expect_flag("weight stream reached bottom row of both columns", done_seen_local == 2'b11);
    expect_flag("weight FIFO is empty after loading one tile", wgt_fifo_empty_o == 1'b1);
  endtask

  task automatic stream_activation_pair(
      input logic signed [DATA_WIDTH-1:0] lane0,
      input logic signed [DATA_WIDTH-1:0] lane1
  );
    @(negedge clk);
    act_flat_raw_i  = pack_pair(lane0, lane1);
    act_valid_raw_i = 2'b11;
    work_i          = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    act_flat_raw_i  = '0;
    act_valid_raw_i = '0;
    work_i          = 1'b0;
  endtask

  task automatic observe_outputs();
    for (int cycle = 0; cycle < 80; cycle++) begin
      @(posedge clk);
      #1;

      for (int col = 0; col < SIZE; col++) begin
        if (psum_valid_o[col] && !captured_valid[col]) begin
          captured_valid[col] = 1'b1;
          captured_psum[col]  = get_psum(col);
        end
      end

      if (done_o && !done_seen) begin
        done_seen = 1'b1;
        for (int col = 0; col < SIZE; col++) begin
          captured_result[col] = get_result(col);
        end
      end
    end
  endtask

  initial begin
    init_signals();
    reset_dut();

    expect_flag("FIFO is empty after reset", wgt_fifo_empty_o == 1'b1);
    expect_flag("FIFO is not full after reset", wgt_fifo_full_o == 1'b0);

    load_weights_from_fifo();
    stream_activation_pair(8'sd2, -8'sd1);
    observe_outputs();

    expect_flag("column 0 produced a psum", captured_valid[0]);
    expect_flag("column 1 produced a psum", captured_valid[1]);
    expect_psum_eq("column 0 weighted sum", captured_psum[0], 17'sd3);
    expect_psum_eq("column 1 weighted sum", captured_psum[1], -17'sd7);
    expect_flag("local output accumulators asserted done", done_seen);
    expect_acc_eq("accumulator result column 0", captured_result[0], 32'sd3);
    expect_acc_eq("accumulator result column 1", captured_result[1], -32'sd7);
    expect_flag("no PE overflow while testing weight FIFO/fetcher", overflow_flatten_o == '0);

    $display("test_weight_fifo_fetcher_mxu: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_weight_fifo_fetcher_mxu failed");
    end
    $finish;
  end

endmodule : test_weight_fifo_fetcher_mxu
