`timescale 1ns / 1ps

module test_weight_tile_buffer_v3;
  localparam int ARRAY_K = 2;
  localparam int ARRAY_OC = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ADDR_WIDTH = 8;
  localparam int TAG_WIDTH = 16;
  localparam int TILE_ELEMS = ARRAY_K * ARRAY_OC;
  localparam int CLK_PERIOD = 10;

  logic clk;
  logic rst_n;
  logic clear_i;
  logic tile_release_i;

  logic req_valid_i;
  logic req_ready_o;
  logic [TILE_ELEMS*ADDR_WIDTH-1:0] req_addr_flatten_i;
  logic [TILE_ELEMS-1:0] req_weight_valid_i;
  logic [TILE_ELEMS-1:0] req_weight_zero_i;
  logic [TAG_WIDTH-1:0] req_tag_i;

  logic weight_rd_en_o;
  logic [ADDR_WIDTH-1:0] weight_rd_addr_o;
  logic signed [DATA_WIDTH-1:0] weight_rd_data_i;
  logic weight_rd_valid_i;

  logic signed [TILE_ELEMS*DATA_WIDTH-1:0] tile_flatten_o;
  logic [TILE_ELEMS-1:0] tile_valid_mask_o;
  logic [TAG_WIDTH-1:0] tile_tag_o;
  logic tile_valid_o;

  logic stream_start_i;
  logic stream_ready_o;
  logic signed [ARRAY_OC*DATA_WIDTH-1:0] wgt_row_flatten_o;
  logic [ARRAY_OC-1:0] wgt_row_load_o;
  logic weight_switch_o;
  logic stream_done_o;

  logic busy_o;
  logic [31:0] dbg_weight_load_cycles_o;
  logic [31:0] dbg_weight_reuse_count_o;
  logic [31:0] dbg_weight_buffer_empty_cycles_o;
  logic [31:0] dbg_weight_buffer_full_cycles_o;

  logic signed [DATA_WIDTH-1:0] weight_mem[0:(1<<ADDR_WIDTH)-1];

  int checks;
  int passes;
  int fails;
  int full_cycles_before;

  weight_tile_buffer_v3 #(
      .ARRAY_K   (ARRAY_K),
      .ARRAY_OC  (ARRAY_OC),
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .TAG_WIDTH (TAG_WIDTH)
  ) dut (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .clear_i                          (clear_i),
      .tile_release_i                   (tile_release_i),
      .req_valid_i                      (req_valid_i),
      .req_ready_o                      (req_ready_o),
      .req_addr_flatten_i               (req_addr_flatten_i),
      .req_weight_valid_i               (req_weight_valid_i),
      .req_weight_zero_i                (req_weight_zero_i),
      .req_tag_i                        (req_tag_i),
      .weight_rd_en_o                   (weight_rd_en_o),
      .weight_rd_addr_o                 (weight_rd_addr_o),
      .weight_rd_data_i                 (weight_rd_data_i),
      .weight_rd_valid_i                (weight_rd_valid_i),
      .tile_flatten_o                   (tile_flatten_o),
      .tile_valid_mask_o                (tile_valid_mask_o),
      .tile_tag_o                       (tile_tag_o),
      .tile_valid_o                     (tile_valid_o),
      .stream_start_i                   (stream_start_i),
      .stream_ready_o                   (stream_ready_o),
      .wgt_row_flatten_o                (wgt_row_flatten_o),
      .wgt_row_load_o                   (wgt_row_load_o),
      .weight_switch_o                  (weight_switch_o),
      .stream_done_o                    (stream_done_o),
      .busy_o                           (busy_o),
      .dbg_weight_load_cycles_o         (dbg_weight_load_cycles_o),
      .dbg_weight_reuse_count_o         (dbg_weight_reuse_count_o),
      .dbg_weight_buffer_empty_cycles_o (dbg_weight_buffer_empty_cycles_o),
      .dbg_weight_buffer_full_cycles_o  (dbg_weight_buffer_full_cycles_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_rd_data_i <= '0;
      weight_rd_valid_i <= 1'b0;
    end else begin
      weight_rd_valid_i <= weight_rd_en_o;
      if (weight_rd_en_o) begin
        weight_rd_data_i <= weight_mem[weight_rd_addr_o];
        $display("[%0t] WGT RD: addr=%0d data=%0d",
                 $time, weight_rd_addr_o, weight_mem[weight_rd_addr_o]);
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

  task automatic init_signals();
    begin
      rst_n = 1'b0;
      clear_i = 1'b0;
      tile_release_i = 1'b0;
      req_valid_i = 1'b0;
      req_addr_flatten_i = '0;
      req_weight_valid_i = '0;
      req_weight_zero_i = '0;
      req_tag_i = '0;
      stream_start_i = 1'b0;
      checks = 0;
      passes = 0;
      fails = 0;

      for (int idx = 0; idx < (1 << ADDR_WIDTH); idx++) begin
        weight_mem[idx] = $signed(idx - 64);
      end

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic set_tile_addrs(
      input logic [ADDR_WIDTH-1:0] addr00,
      input logic [ADDR_WIDTH-1:0] addr01,
      input logic [ADDR_WIDTH-1:0] addr10,
      input logic [ADDR_WIDTH-1:0] addr11);
    begin
      req_addr_flatten_i[(0*ADDR_WIDTH)+:ADDR_WIDTH] = addr00;
      req_addr_flatten_i[(1*ADDR_WIDTH)+:ADDR_WIDTH] = addr01;
      req_addr_flatten_i[(2*ADDR_WIDTH)+:ADDR_WIDTH] = addr10;
      req_addr_flatten_i[(3*ADDR_WIDTH)+:ADDR_WIDTH] = addr11;
    end
  endtask

  task automatic send_tile_req(
      input logic [ADDR_WIDTH-1:0] addr00,
      input logic [ADDR_WIDTH-1:0] addr01,
      input logic [ADDR_WIDTH-1:0] addr10,
      input logic [ADDR_WIDTH-1:0] addr11,
      input logic [TILE_ELEMS-1:0] valid_mask,
      input logic [TILE_ELEMS-1:0] zero_mask,
      input logic [TAG_WIDTH-1:0] tag);
    begin
      $display("  REQ    : tag=0x%04h addr={{r1c1:%0d,r1c0:%0d},{r0c1:%0d,r0c0:%0d}} valid=%b zero=%b",
               tag, addr11, addr10, addr01, addr00, valid_mask, zero_mask);
      @(negedge clk);
      set_tile_addrs(addr00, addr01, addr10, addr11);
      req_weight_valid_i = valid_mask;
      req_weight_zero_i = zero_mask;
      req_tag_i = tag;
      req_valid_i = 1'b1;
      do begin
        @(posedge clk);
      end while (!req_ready_o);
      @(negedge clk);
      req_valid_i = 1'b0;
      req_addr_flatten_i = '0;
      req_weight_valid_i = '0;
      req_weight_zero_i = '0;
      req_tag_i = '0;
    end
  endtask

  task automatic wait_tile_valid(
      input int exp00,
      input int exp01,
      input int exp10,
      input int exp11,
      input logic [TILE_ELEMS-1:0] exp_valid,
      input logic [TAG_WIDTH-1:0] exp_tag);
    int timeout;
    begin
      timeout = 200;
      while (!tile_valid_o && timeout > 0) begin
        @(posedge clk);
        timeout--;
      end

      #1;
      $display("  TILE   : tag=0x%04h valid=%b data={{r1c1:%0d,r1c0:%0d},{r0c1:%0d,r0c0:%0d}}",
               tile_tag_o, tile_valid_mask_o,
               $signed(tile_flatten_o[(3*DATA_WIDTH)+:DATA_WIDTH]),
               $signed(tile_flatten_o[(2*DATA_WIDTH)+:DATA_WIDTH]),
               $signed(tile_flatten_o[(1*DATA_WIDTH)+:DATA_WIDTH]),
               $signed(tile_flatten_o[(0*DATA_WIDTH)+:DATA_WIDTH]));
      expect_flag("tile valid", tile_valid_o);
      expect_i32("tile r0c0", $signed(tile_flatten_o[(0*DATA_WIDTH)+:DATA_WIDTH]), exp00);
      expect_i32("tile r0c1", $signed(tile_flatten_o[(1*DATA_WIDTH)+:DATA_WIDTH]), exp01);
      expect_i32("tile r1c0", $signed(tile_flatten_o[(2*DATA_WIDTH)+:DATA_WIDTH]), exp10);
      expect_i32("tile r1c1", $signed(tile_flatten_o[(3*DATA_WIDTH)+:DATA_WIDTH]), exp11);
      expect_i32("tile valid mask", int'(tile_valid_mask_o), int'(exp_valid));
      expect_i32("tile tag", int'(tile_tag_o), int'(exp_tag));
    end
  endtask

  task automatic expect_stream_once(
      input int exp00,
      input int exp01,
      input int exp10,
      input int exp11);
    begin
      @(negedge clk);
      stream_start_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      stream_start_i = 1'b0;

      #1;
      $display("  STREAM : row1(bottom) load=%b data={c1:%0d,c0:%0d}",
               wgt_row_load_o,
               $signed(wgt_row_flatten_o[(1*DATA_WIDTH)+:DATA_WIDTH]),
               $signed(wgt_row_flatten_o[(0*DATA_WIDTH)+:DATA_WIDTH]));
      expect_i32("stream row1 c0", $signed(wgt_row_flatten_o[(0*DATA_WIDTH)+:DATA_WIDTH]), exp10);
      expect_i32("stream row1 c1", $signed(wgt_row_flatten_o[(1*DATA_WIDTH)+:DATA_WIDTH]), exp11);
      expect_i32("stream row1 load", int'(wgt_row_load_o), 3);

      @(posedge clk);
      #1;
      $display("  STREAM : row0(top) load=%b data={c1:%0d,c0:%0d}",
               wgt_row_load_o,
               $signed(wgt_row_flatten_o[(1*DATA_WIDTH)+:DATA_WIDTH]),
               $signed(wgt_row_flatten_o[(0*DATA_WIDTH)+:DATA_WIDTH]));
      expect_i32("stream row0 c0", $signed(wgt_row_flatten_o[(0*DATA_WIDTH)+:DATA_WIDTH]), exp00);
      expect_i32("stream row0 c1", $signed(wgt_row_flatten_o[(1*DATA_WIDTH)+:DATA_WIDTH]), exp01);
      expect_i32("stream row0 load", int'(wgt_row_load_o), 3);

      @(posedge clk);
      #1;
      $display("  SWITCH : weight_switch=%0b stream_done=%0b",
               weight_switch_o, stream_done_o);
      expect_flag("weight switch pulse", weight_switch_o);
      expect_flag("stream done pulse", stream_done_o);

      @(posedge clk);
      #1;
    end
  endtask

  task automatic release_tile();
    begin
      @(negedge clk);
      tile_release_i = 1'b1;
      @(negedge clk);
      tile_release_i = 1'b0;
      #1;
      $display("  RELEASE: tile_valid=%0b req_ready=%0b", tile_valid_o, req_ready_o);
      expect_flag("tile released", !tile_valid_o);
      expect_flag("request ready after release", req_ready_o);
    end
  endtask

  task automatic release_tile_expect_next(
      input int exp00,
      input int exp01,
      input int exp10,
      input int exp11,
      input logic [TILE_ELEMS-1:0] exp_valid,
      input logic [TAG_WIDTH-1:0] exp_tag);
    int timeout;
    begin
      @(negedge clk);
      tile_release_i = 1'b1;
      @(negedge clk);
      tile_release_i = 1'b0;

      timeout = 200;
      while ((!tile_valid_o || tile_tag_o != exp_tag) && timeout > 0) begin
        @(posedge clk);
        timeout--;
      end

      #1;
      $display("  RELEASE: next tile_valid=%0b tag=0x%04h req_ready=%0b",
               tile_valid_o, tile_tag_o, req_ready_o);
      wait_tile_valid(exp00, exp01, exp10, exp11, exp_valid, exp_tag);
    end
  endtask

  initial begin
    init_signals();

    $display("");
    $display("============================================================");
    $display("TEST: weight tile stream before load");
    $display("============================================================");
    @(negedge clk);
    stream_start_i = 1'b1;
    @(negedge clk);
    stream_start_i = 1'b0;
    $display("  EMPTY  : stream_ready=%0b empty_cycles=%0d",
             stream_ready_o, dbg_weight_buffer_empty_cycles_o);
    expect_flag("empty stream counted", dbg_weight_buffer_empty_cycles_o != 32'd0);

    $display("");
    $display("============================================================");
    $display("TEST: weight tile normal load");
    $display("============================================================");
    send_tile_req(8'd70, 8'd71, 8'd72, 8'd73, 4'b1111, 4'b0000, 16'h0101);
    wait_tile_valid(6, 7, 8, 9, 4'b1111, 16'h0101);

    $display("");
    $display("============================================================");
    $display("TEST: weight tile repeated stream reuse");
    $display("============================================================");
    expect_stream_once(6, 7, 8, 9);
    expect_stream_once(6, 7, 8, 9);
    expect_i32("reuse count after two streams", int'(dbg_weight_reuse_count_o), 2);

    $display("");
    $display("============================================================");
    $display("TEST: prefetch request while tile is resident");
    $display("============================================================");
    full_cycles_before = int'(dbg_weight_buffer_full_cycles_o);
    send_tile_req(8'd80, 8'd81, 8'd82, 8'd83, 4'b1011, 4'b0010, 16'h0202);
    while (busy_o) begin
      @(posedge clk);
    end
    #1;
    $display("  PREFETCH: active tag=0x%04h full_cycles=%0d",
             tile_tag_o, dbg_weight_buffer_full_cycles_o);
    expect_i32("active tile unchanged during prefetch", int'(tile_tag_o), 16'h0101);
    expect_i32("resident prefetch did not block", int'(dbg_weight_buffer_full_cycles_o), full_cycles_before);

    $display("");
    $display("============================================================");
    $display("TEST: prefetched padded/invalid tile becomes active after release");
    $display("============================================================");
    release_tile_expect_next(16, 0, 0, 19, 4'b1011, 16'h0202);
    expect_stream_once(16, 0, 0, 19);

    expect_flag("tile valid at end", tile_valid_o);
    expect_flag("not busy at end", !busy_o);

    $display("");
    $display("DEBUG COUNTERS");
    $display("  weight_load_cycles=%0d weight_reuse_count=%0d empty_cycles=%0d full_cycles=%0d",
             dbg_weight_load_cycles_o, dbg_weight_reuse_count_o,
             dbg_weight_buffer_empty_cycles_o, dbg_weight_buffer_full_cycles_o);

    $display("test_weight_tile_buffer_v3: checks=%0d pass=%0d fail=%0d",
             checks, passes, fails);
    if (fails != 0) begin
      $fatal(1, "test_weight_tile_buffer_v3 failed");
    end
    $finish;
  end

endmodule : test_weight_tile_buffer_v3
