`timescale 1ns / 1ps

module test_maxpool2d_pool1;

  localparam int DATA_WIDTH = 8;
  localparam int UB_BANK_DEPTH = 8192;
  localparam int UB_ADDR_WIDTH = $clog2(UB_BANK_DEPTH);
  localparam int CLK_PERIOD = 10;
  localparam int TIMEOUT_CYCLES = 50000;

  localparam int CONV1_C = 8;
  localparam int CONV1_H = 26;
  localparam int CONV1_W = 26;
  localparam int POOL1_H = 13;
  localparam int POOL1_W = 13;
  localparam int CONV1_OUT_COUNT = CONV1_C * CONV1_H * CONV1_W;
  localparam int POOL1_OUT_COUNT = CONV1_C * POOL1_H * POOL1_W;

  logic clk;
  logic rst_n;

  logic signed [DATA_WIDTH-1:0] conv1_out_mem[0:CONV1_OUT_COUNT-1];
  logic signed [DATA_WIDTH-1:0] expected_pool_mem[0:POOL1_OUT_COUNT-1];

  logic host_mode;
  logic host_rd_en;
  logic host_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] host_rd_addr;
  logic host_wr_en;
  logic host_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] host_wr_addr;
  logic signed [DATA_WIDTH-1:0] host_wr_data;

  logic pool_rd_en;
  logic pool_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] pool_rd_addr;
  logic pool_wr_en;
  logic pool_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] pool_wr_addr;
  logic signed [DATA_WIDTH-1:0] pool_wr_data;

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
  logic pool_done_o;
  logic pool_busy_o;
  logic pool_error_o;
  logic [3:0] pool_state_o;
  logic [15:0] pool_channel_o;
  logic [15:0] pool_out_row_o;
  logic [15:0] pool_out_col_o;
  logic [31:0] pool_error_code_o;

  int test_count;
  int pass_count;
  int fail_count;
  int write_count;

  assign ub_rd_en   = host_mode ? host_rd_en   : pool_rd_en;
  assign ub_rd_bank = host_mode ? host_rd_bank : pool_rd_bank;
  assign ub_rd_addr = host_mode ? host_rd_addr : pool_rd_addr;
  assign ub_wr_en   = host_mode ? host_wr_en   : pool_wr_en;
  assign ub_wr_bank = host_mode ? host_wr_bank : pool_wr_bank;
  assign ub_wr_addr = host_mode ? host_wr_addr : pool_wr_addr;
  assign ub_wr_data = host_mode ? host_wr_data : pool_wr_data;

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

  maxpool2d #(
      .DATA_WIDTH(DATA_WIDTH),
      .BANK_DEPTH(UB_BANK_DEPTH),
      .ADDR_WIDTH(UB_ADDR_WIDTH),
      .DIM_WIDTH (16)
  ) u_maxpool2d_unit (
      .clk               (clk),
      .rst_n             (rst_n),
      .start_i           (start_i),
      .done_o            (pool_done_o),
      .busy_o            (pool_busy_o),
      .error_o           (pool_error_o),
      .dbg_state_o       (pool_state_o),
      .dbg_channel_o     (pool_channel_o),
      .dbg_out_row_o     (pool_out_row_o),
      .dbg_out_col_o     (pool_out_col_o),
      .dbg_error_code_o  (pool_error_code_o),
      .read_bank_i       (1'b1),
      .write_bank_i      (1'b0),
      .input_base_addr_i ('0),
      .output_base_addr_i('0),
      .in_h_i            (16'(CONV1_H)),
      .in_w_i            (16'(CONV1_W)),
      .channels_i        (16'(CONV1_C)),
      .out_h_i           (16'(POOL1_H)),
      .out_w_i           (16'(POOL1_W)),
      .ub_rd_en_o        (pool_rd_en),
      .ub_rd_bank_o      (pool_rd_bank),
      .ub_rd_addr_o      (pool_rd_addr),
      .ub_rd_data_i      (ub_rd_data),
      .ub_rd_valid_i     (ub_rd_valid),
      .ub_wr_en_o        (pool_wr_en),
      .ub_wr_bank_o      (pool_wr_bank),
      .ub_wr_addr_o      (pool_wr_addr),
      .ub_wr_data_o      (pool_wr_data)
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
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    write_count = 0;
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

  function automatic logic signed [DATA_WIDTH-1:0] max_i8(
      input logic signed [DATA_WIDTH-1:0] a,
      input logic signed [DATA_WIDTH-1:0] b
  );
    max_i8 = (a > b) ? a : b;
  endfunction

  task automatic build_pool1_expected();
    int in_base;
    int out_idx;
    logic signed [DATA_WIDTH-1:0] p00;
    logic signed [DATA_WIDTH-1:0] p01;
    logic signed [DATA_WIDTH-1:0] p10;
    logic signed [DATA_WIDTH-1:0] p11;

    for (int c = 0; c < CONV1_C; c++) begin
      for (int oh = 0; oh < POOL1_H; oh++) begin
        for (int ow = 0; ow < POOL1_W; ow++) begin
          in_base = (c * CONV1_H * CONV1_W) + ((oh * 2) * CONV1_W) + (ow * 2);
          out_idx = (c * POOL1_H * POOL1_W) + (oh * POOL1_W) + ow;
          p00 = conv1_out_mem[in_base];
          p01 = conv1_out_mem[in_base + 1];
          p10 = conv1_out_mem[in_base + CONV1_W];
          p11 = conv1_out_mem[in_base + CONV1_W + 1];
          expected_pool_mem[out_idx] = max_i8(max_i8(p00, p01), max_i8(p10, p11));
        end
      end
    end
  endtask

  task automatic preload_conv1_output();
    print_header("TEST: Host preload Conv1 output tensor");
    host_mode = 1'b1;
    $readmemh("../../../CNN_model/python/mnist_classification/18_05/layer0_out_i8.hex",
              conv1_out_mem);
    build_pool1_expected();
    for (int idx = 0; idx < CONV1_OUT_COUNT; idx++) begin
      host_write(1'b1, UB_ADDR_WIDTH'(idx), conv1_out_mem[idx]);
    end
    $display("  UB bank1[0:%0d] loaded from layer0_out_i8.hex", CONV1_OUT_COUNT - 1);
    $display("  Pool1 expected tensor generated: 8x13x13 channel-major");
  endtask

  task automatic run_pool1();
    int cycles;

    print_header("TEST: MaxPool2d Pool1 pass");
    host_mode = 1'b0;

    @(negedge clk);
    start_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    start_i = 1'b0;

    cycles = 0;
    while (!pool_done_o && !pool_error_o && (cycles < TIMEOUT_CYCLES)) begin
      @(posedge clk);
      #1;
      cycles++;

      if (pool_wr_en) begin
        write_count++;
        if ((write_count % 256) == 0) begin
          $display("  progress: writes=%0d channel=%0d row=%0d col=%0d",
                   write_count, pool_channel_o, pool_out_row_o, pool_out_col_o);
        end
      end
    end

    $display("  POOL   : done=%b error=%b state=%0d channel=%0d row=%0d col=%0d cycles=%0d err=0x%08h",
             pool_done_o, pool_error_o, pool_state_o, pool_channel_o,
             pool_out_row_o, pool_out_col_o, cycles, pool_error_code_o);
    $display("  writes observed: %0d", write_count);

    expect_flag("pool finished", pool_done_o);
    expect_flag("pool no error", !pool_error_o);
    expect_flag("pool wrote all outputs", write_count == POOL1_OUT_COUNT);
  endtask

  task automatic check_pool1_output();
    logic signed [DATA_WIDTH-1:0] actual;
    logic signed [DATA_WIDTH-1:0] sample0;
    logic signed [DATA_WIDTH-1:0] sample_last;
    int mismatch_count;

    print_header("TEST: Host readback Pool1 output tensor");
    host_mode = 1'b1;
    mismatch_count = 0;
    sample0 = '0;
    sample_last = '0;

    for (int idx = 0; idx < POOL1_OUT_COUNT; idx++) begin
      host_read(1'b0, UB_ADDR_WIDTH'(idx), actual);
      test_count++;
      if (actual === expected_pool_mem[idx]) begin
        pass_count++;
      end else begin
        fail_count++;
        mismatch_count++;
        if (mismatch_count <= 8) begin
          $display("FAIL: pool1_out[%0d] got=%0d expected=%0d",
                   idx, $signed(actual), $signed(expected_pool_mem[idx]));
        end
      end

      if (idx == 0) begin
        sample0 = actual;
      end else if (idx == (POOL1_OUT_COUNT - 1)) begin
        sample_last = actual;
      end
    end

    $display("  samples: pool1[0]=%0d pool1[%0d]=%0d",
             $signed(sample0), POOL1_OUT_COUNT - 1, $signed(sample_last));
    $display("  mismatches: %0d", mismatch_count);
  endtask

  initial begin
    init_signals();
    reset_dut();

    preload_conv1_output();
    run_pool1();
    check_pool1_output();

    $display("test_maxpool2d_pool1: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_maxpool2d_pool1 failed");
    end
    $finish;
  end

endmodule : test_maxpool2d_pool1
