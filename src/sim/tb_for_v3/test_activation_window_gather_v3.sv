`timescale 1ns / 1ps

module test_activation_window_gather_v3;
  localparam int ARRAY_K = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ADDR_WIDTH = 8;
  localparam int TAG_WIDTH = 16;
  localparam int FIFO_DEPTH = 2;
  localparam int CLK_PERIOD = 10;

  logic clk;
  logic rst_n;
  logic clear_i;

  logic req_valid_i;
  logic req_ready_o;
  logic [ARRAY_K*ADDR_WIDTH-1:0] req_addr_flatten_i;
  logic [ARRAY_K-1:0] req_lane_valid_i;
  logic [ARRAY_K-1:0] req_lane_zero_i;
  logic [TAG_WIDTH-1:0] req_tag_i;

  logic ub_rd_en_o;
  logic [ADDR_WIDTH-1:0] ub_rd_addr_o;
  logic signed [DATA_WIDTH-1:0] ub_rd_data_i;
  logic ub_rd_valid_i;

  logic signed [ARRAY_K*DATA_WIDTH-1:0] act_vec_flatten_o;
  logic [ARRAY_K-1:0] act_valid_o;
  logic [TAG_WIDTH-1:0] act_tag_o;
  logic act_vec_valid_o;
  logic act_vec_ready_i;

  logic busy_o;
  logic fifo_full_o;
  logic fifo_empty_o;
  logic [31:0] dbg_fetch_cycles_o;
  logic [31:0] dbg_output_stall_cycles_o;
  logic [31:0] dbg_vectors_pushed_o;
  logic [31:0] dbg_lane_reads_o;

  logic signed [DATA_WIDTH-1:0] ub_mem[0:(1<<ADDR_WIDTH)-1];

  int checks;
  int passes;
  int fails;

  activation_window_gather_v3 #(
      .ARRAY_K   (ARRAY_K),
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .TAG_WIDTH (TAG_WIDTH),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
      .clk                      (clk),
      .rst_n                    (rst_n),
      .clear_i                  (clear_i),
      .req_valid_i              (req_valid_i),
      .req_ready_o              (req_ready_o),
      .req_addr_flatten_i       (req_addr_flatten_i),
      .req_lane_valid_i         (req_lane_valid_i),
      .req_lane_zero_i          (req_lane_zero_i),
      .req_tag_i                (req_tag_i),
      .ub_rd_en_o               (ub_rd_en_o),
      .ub_rd_addr_o             (ub_rd_addr_o),
      .ub_rd_data_i             (ub_rd_data_i),
      .ub_rd_valid_i            (ub_rd_valid_i),
      .act_vec_flatten_o        (act_vec_flatten_o),
      .act_valid_o              (act_valid_o),
      .act_tag_o                (act_tag_o),
      .act_vec_valid_o          (act_vec_valid_o),
      .act_vec_ready_i          (act_vec_ready_i),
      .busy_o                   (busy_o),
      .fifo_full_o              (fifo_full_o),
      .fifo_empty_o             (fifo_empty_o),
      .dbg_fetch_cycles_o       (dbg_fetch_cycles_o),
      .dbg_output_stall_cycles_o(dbg_output_stall_cycles_o),
      .dbg_vectors_pushed_o     (dbg_vectors_pushed_o),
      .dbg_lane_reads_o         (dbg_lane_reads_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ub_rd_data_i <= '0;
      ub_rd_valid_i <= 1'b0;
    end else begin
      ub_rd_valid_i <= ub_rd_en_o;
      if (ub_rd_en_o) begin
        ub_rd_data_i <= ub_mem[ub_rd_addr_o];
        $display("[%0t] UB RD : addr=%0d data=%0d",
                 $time, ub_rd_addr_o, ub_mem[ub_rd_addr_o]);
      end
    end
  end

  task automatic expect_flag(input string label, input logic condition);
    checks++;
    if (condition) begin
      passes++;
    end else begin
      fails++;
      $display("FAIL: %s", label);
    end
  endtask

  task automatic expect_i32(input string label, input int got, input int expected);
    checks++;
    if (got == expected) begin
      passes++;
    end else begin
      fails++;
      $display("FAIL: %s got=%0d expected=%0d", label, got, expected);
    end
  endtask

  task automatic send_req(
      input logic [ADDR_WIDTH-1:0] addr0,
      input logic [ADDR_WIDTH-1:0] addr1,
      input logic [ARRAY_K-1:0] valid_mask,
      input logic [ARRAY_K-1:0] zero_mask,
      input logic [TAG_WIDTH-1:0] tag);
    begin
      $display("  REQ    : tag=0x%04h addr={lane1:%0d,lane0:%0d} valid=%b zero=%b",
               tag, addr1, addr0, valid_mask, zero_mask);
      @(negedge clk);
      req_addr_flatten_i = {addr1, addr0};
      req_lane_valid_i = valid_mask;
      req_lane_zero_i = zero_mask;
      req_tag_i = tag;
      req_valid_i = 1'b1;
      do begin
        @(posedge clk);
      end while (!req_ready_o);
      @(negedge clk);
      req_valid_i = 1'b0;
      req_addr_flatten_i = '0;
      req_lane_valid_i = '0;
      req_lane_zero_i = '0;
      req_tag_i = '0;
    end
  endtask

  task automatic expect_output(
      input int exp_lane0,
      input int exp_lane1,
      input logic [ARRAY_K-1:0] exp_valid,
      input logic [TAG_WIDTH-1:0] exp_tag);
    int timeout;
    begin
      timeout = 100;
      while (!act_vec_valid_o && timeout > 0) begin
        @(posedge clk);
        timeout--;
      end

      #1;
      $display("  OUT    : tag=0x%04h valid=%b data={lane1:%0d,lane0:%0d}",
               act_tag_o, act_valid_o,
               $signed(act_vec_flatten_o[DATA_WIDTH+:DATA_WIDTH]),
               $signed(act_vec_flatten_o[0+:DATA_WIDTH]));
      $display("  EXPECT : tag=0x%04h valid=%b data={lane1:%0d,lane0:%0d}",
               exp_tag, exp_valid, exp_lane1, exp_lane0);
      expect_flag("output valid", act_vec_valid_o);
      expect_i32("lane0 data", $signed(act_vec_flatten_o[0+:DATA_WIDTH]), exp_lane0);
      expect_i32("lane1 data", $signed(act_vec_flatten_o[DATA_WIDTH+:DATA_WIDTH]), exp_lane1);
      expect_i32("valid mask", int'(act_valid_o), int'(exp_valid));
      expect_i32("tag", int'(act_tag_o), int'(exp_tag));

      @(negedge clk);
      act_vec_ready_i = 1'b1;
      @(negedge clk);
      act_vec_ready_i = 1'b0;
    end
  endtask

  task automatic init_signals();
    begin
      rst_n = 1'b0;
      clear_i = 1'b0;
      req_valid_i = 1'b0;
      req_addr_flatten_i = '0;
      req_lane_valid_i = '0;
      req_lane_zero_i = '0;
      req_tag_i = '0;
      act_vec_ready_i = 1'b0;
      checks = 0;
      passes = 0;
      fails = 0;

      for (int idx = 0; idx < (1 << ADDR_WIDTH); idx++) begin
        ub_mem[idx] = $signed(idx - 64);
      end

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  initial begin
    init_signals();

    $display("");
    $display("============================================================");
    $display("TEST: activation gather normal vector");
    $display("============================================================");
    send_req(8'd70, 8'd71, 2'b11, 2'b00, 16'h0011);
    expect_output(6, 7, 2'b11, 16'h0011);

    $display("");
    $display("============================================================");
    $display("TEST: activation gather padded zero lane");
    $display("============================================================");
    send_req(8'd72, 8'd0, 2'b11, 2'b10, 16'h0022);
    expect_output(8, 0, 2'b11, 16'h0022);

    $display("");
    $display("============================================================");
    $display("TEST: activation gather invalid lane");
    $display("============================================================");
    send_req(8'd73, 8'd74, 2'b01, 2'b00, 16'h0033);
    expect_output(9, 0, 2'b01, 16'h0033);

    $display("");
    $display("============================================================");
    $display("TEST: activation gather output backpressure");
    $display("============================================================");
    send_req(8'd75, 8'd76, 2'b11, 2'b00, 16'h0044);
    while (!act_vec_valid_o) begin
      @(posedge clk);
    end
    repeat (4) @(posedge clk);
    #1;
    $display("  HOLD   : ready=0 cycles=4 valid=%b data={lane1:%0d,lane0:%0d} stall_cycles=%0d",
             act_vec_valid_o,
             $signed(act_vec_flatten_o[DATA_WIDTH+:DATA_WIDTH]),
             $signed(act_vec_flatten_o[0+:DATA_WIDTH]),
             dbg_output_stall_cycles_o);
    expect_i32("backpressure lane0 stable", $signed(act_vec_flatten_o[0+:DATA_WIDTH]), 11);
    expect_i32("backpressure lane1 stable", $signed(act_vec_flatten_o[DATA_WIDTH+:DATA_WIDTH]), 12);
    expect_flag("stall counter increments", dbg_output_stall_cycles_o != 32'd0);
    expect_output(11, 12, 2'b11, 16'h0044);

    expect_i32("vectors pushed", int'(dbg_vectors_pushed_o), 4);
    expect_i32("lane reads skip zero/invalid lanes", int'(dbg_lane_reads_o), 6);
    expect_flag("fifo empty at end", fifo_empty_o);
    expect_flag("not busy at end", !busy_o);

    $display("");
    $display("DEBUG COUNTERS");
    $display("  fetch_cycles=%0d output_stall_cycles=%0d vectors_pushed=%0d lane_reads=%0d",
             dbg_fetch_cycles_o, dbg_output_stall_cycles_o,
             dbg_vectors_pushed_o, dbg_lane_reads_o);
    $display("  fifo_empty=%0b fifo_full=%0b busy=%0b",
             fifo_empty_o, fifo_full_o, busy_o);

    $display("test_activation_window_gather_v3: checks=%0d pass=%0d fail=%0d",
             checks, passes, fails);
    if (fails != 0) begin
      $fatal(1, "test_activation_window_gather_v3 failed");
    end
    $finish;
  end

endmodule : test_activation_window_gather_v3
