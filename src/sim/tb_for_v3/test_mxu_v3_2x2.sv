`timescale 1ns / 1ps

module test_mxu_v3_2x2;
  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ACT_ADDR_WIDTH = 8;
  localparam int WGT_ADDR_WIDTH = 8;
  localparam int TAG_WIDTH = 16;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = 1;
  localparam int ACC_WIDTH = 32;
  localparam int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1;
  localparam int MAC_COUNT_WIDTH = (SIZE*SIZE > 1) ? $clog2((SIZE*SIZE) + 1) : 1;
  localparam int CLK_PERIOD = 10;

  logic clk;
  logic rst_n;
  logic clear_i;
  logic compute_enable_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_i;

  logic act_req_valid_i;
  logic act_req_ready_o;
  logic [SIZE*ACT_ADDR_WIDTH-1:0] act_req_addr_flatten_i;
  logic [SIZE-1:0] act_req_lane_valid_i;
  logic [SIZE-1:0] act_req_lane_zero_i;
  logic [TAG_WIDTH-1:0] act_req_tag_i;

  logic ub_rd_en_o;
  logic [ACT_ADDR_WIDTH-1:0] ub_rd_addr_o;
  logic signed [DATA_WIDTH-1:0] ub_rd_data_i;
  logic ub_rd_valid_i;

  logic wgt_req_valid_i;
  logic wgt_req_ready_o;
  logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0] wgt_req_addr_flatten_i;
  logic [SIZE*SIZE-1:0] wgt_req_valid_mask_i;
  logic [SIZE*SIZE-1:0] wgt_req_zero_mask_i;
  logic [TAG_WIDTH-1:0] wgt_req_tag_i;
  logic wgt_tile_release_i;
  logic wgt_stream_start_i;
  logic wgt_stream_ready_o;
  logic wgt_tile_valid_o;
  logic [TAG_WIDTH-1:0] wgt_tile_tag_o;
  logic wgt_stream_done_o;

  logic weight_rd_en_o;
  logic [WGT_ADDR_WIDTH-1:0] weight_rd_addr_o;
  logic signed [DATA_WIDTH-1:0] weight_rd_data_i;
  logic weight_rd_valid_i;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o;
  logic [SIZE-1:0] psum_valid_o;
  logic [MAC_COUNT_WIDTH-1:0] valid_mac_count_o;
  logic signed [(ACC_WIDTH*SIZE)-1:0] result_flatten_o;
  logic done_o;
  logic [SIZE-1:0] wgt_load_done_o;
  logic overflow_clr_i;
  logic [SIZE*SIZE-1:0] overflow_flatten_o;

  logic busy_o;
  logic [31:0] dbg_act_fetch_cycles_o;
  logic [31:0] dbg_act_output_stall_cycles_o;
  logic [31:0] dbg_act_vectors_pushed_o;
  logic [31:0] dbg_act_lane_reads_o;
  logic [31:0] dbg_weight_load_cycles_o;
  logic [31:0] dbg_weight_reuse_count_o;
  logic [31:0] dbg_weight_buffer_empty_cycles_o;
  logic [31:0] dbg_weight_buffer_full_cycles_o;

  logic signed [DATA_WIDTH-1:0] ub_mem[0:(1<<ACT_ADDR_WIDTH)-1];
  logic signed [DATA_WIDTH-1:0] weight_mem[0:(1<<WGT_ADDR_WIDTH)-1];

  int checks;
  int passes;
  int fails;

  logic signed [LOCAL_PSUM_WIDTH-1:0] captured_psum[0:SIZE-1];
  logic [SIZE-1:0] captured_valid;

  mxu_v3 #(
      .SIZE            (SIZE),
      .DATA_WIDTH      (DATA_WIDTH),
      .ACT_ADDR_WIDTH  (ACT_ADDR_WIDTH),
      .WGT_ADDR_WIDTH  (WGT_ADDR_WIDTH),
      .TAG_WIDTH       (TAG_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .NUM_TILES       (NUM_TILES),
      .ACC_WIDTH       (ACC_WIDTH)
  ) dut (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .clear_i                          (clear_i),
      .compute_enable_i                 (compute_enable_i),
      .num_tiles_i                      (num_tiles_i),
      .act_req_valid_i                  (act_req_valid_i),
      .act_req_ready_o                  (act_req_ready_o),
      .act_req_addr_flatten_i           (act_req_addr_flatten_i),
      .act_req_lane_valid_i             (act_req_lane_valid_i),
      .act_req_lane_zero_i              (act_req_lane_zero_i),
      .act_req_tag_i                    (act_req_tag_i),
      .act_launch_i                     (1'b0),
      .act_launch_ready_o               (),
      .ub_rd_en_o                       (ub_rd_en_o),
      .ub_rd_addr_o                     (ub_rd_addr_o),
      .ub_rd_data_i                     (ub_rd_data_i),
      .ub_rd_valid_i                    (ub_rd_valid_i),
      .wgt_req_valid_i                  (wgt_req_valid_i),
      .wgt_req_ready_o                  (wgt_req_ready_o),
      .wgt_req_addr_flatten_i           (wgt_req_addr_flatten_i),
      .wgt_req_valid_mask_i             (wgt_req_valid_mask_i),
      .wgt_req_zero_mask_i              (wgt_req_zero_mask_i),
      .wgt_req_tag_i                    (wgt_req_tag_i),
      .wgt_tile_release_i               (wgt_tile_release_i),
      .wgt_stream_start_i               (wgt_stream_start_i),
      .wgt_stream_ready_o               (wgt_stream_ready_o),
      .wgt_tile_valid_o                 (wgt_tile_valid_o),
      .wgt_tile_tag_o                   (wgt_tile_tag_o),
      .wgt_stream_done_o                (wgt_stream_done_o),
      .weight_rd_en_o                   (weight_rd_en_o),
      .weight_rd_addr_o                 (weight_rd_addr_o),
      .weight_rd_data_i                 (weight_rd_data_i),
      .weight_rd_valid_i                (weight_rd_valid_i),
      .psum_flatten_o                   (psum_flatten_o),
      .psum_valid_o                     (psum_valid_o),
      .valid_mac_count_o                (valid_mac_count_o),
      .result_flatten_o                 (result_flatten_o),
      .done_o                           (done_o),
      .wgt_load_done_o                  (wgt_load_done_o),
      .overflow_clr_i                   (overflow_clr_i),
      .overflow_flatten_o               (overflow_flatten_o),
      .busy_o                           (busy_o),
      .dbg_act_fetch_cycles_o           (dbg_act_fetch_cycles_o),
      .dbg_act_output_stall_cycles_o    (dbg_act_output_stall_cycles_o),
      .dbg_act_vectors_pushed_o         (dbg_act_vectors_pushed_o),
      .dbg_act_lane_reads_o             (dbg_act_lane_reads_o),
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

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_psum(input int lane);
    get_psum = psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

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
      compute_enable_i = 1'b1;
      num_tiles_i = TILE_COUNT_WIDTH'(NUM_TILES);
      act_req_valid_i = 1'b0;
      act_req_addr_flatten_i = '0;
      act_req_lane_valid_i = '0;
      act_req_lane_zero_i = '0;
      act_req_tag_i = '0;
      wgt_req_valid_i = 1'b0;
      wgt_req_addr_flatten_i = '0;
      wgt_req_valid_mask_i = '0;
      wgt_req_zero_mask_i = '0;
      wgt_req_tag_i = '0;
      wgt_tile_release_i = 1'b0;
      wgt_stream_start_i = 1'b0;
      overflow_clr_i = 1'b0;
      checks = 0;
      passes = 0;
      fails = 0;
      captured_valid = '0;

      for (int idx = 0; idx < (1 << ACT_ADDR_WIDTH); idx++) begin
        ub_mem[idx] = '0;
      end

      for (int idx = 0; idx < (1 << WGT_ADDR_WIDTH); idx++) begin
        weight_mem[idx] = '0;
      end

      ub_mem[20] = 8'sd4;
      ub_mem[21] = 8'sd6;
      ub_mem[22] = -8'sd1;
      ub_mem[23] = 8'sd2;

      weight_mem[10] = 8'sd2;
      weight_mem[11] = -8'sd3;
      weight_mem[12] = 8'sd5;
      weight_mem[13] = -8'sd7;

      for (int lane = 0; lane < SIZE; lane++) begin
        captured_psum[lane] = '0;
      end

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic send_weight_tile_req();
    begin
      $display("  WGT REQ: W=[[2,-3],[5,-7]] addr={{r1c1:13,r1c0:12},{r0c1:11,r0c0:10}}");
      @(negedge clk);
      wgt_req_addr_flatten_i[(0*WGT_ADDR_WIDTH)+:WGT_ADDR_WIDTH] = 8'd10;
      wgt_req_addr_flatten_i[(1*WGT_ADDR_WIDTH)+:WGT_ADDR_WIDTH] = 8'd11;
      wgt_req_addr_flatten_i[(2*WGT_ADDR_WIDTH)+:WGT_ADDR_WIDTH] = 8'd12;
      wgt_req_addr_flatten_i[(3*WGT_ADDR_WIDTH)+:WGT_ADDR_WIDTH] = 8'd13;
      wgt_req_valid_mask_i = 4'b1111;
      wgt_req_zero_mask_i = 4'b0000;
      wgt_req_tag_i = 16'h0a0a;
      wgt_req_valid_i = 1'b1;
      do begin
        @(posedge clk);
      end while (!wgt_req_ready_o);
      @(negedge clk);
      wgt_req_valid_i = 1'b0;
      wgt_req_addr_flatten_i = '0;
      wgt_req_valid_mask_i = '0;
      wgt_req_zero_mask_i = '0;
      wgt_req_tag_i = '0;
    end
  endtask

  task automatic wait_weight_tile_loaded();
    int timeout;
    begin
      timeout = 200;
      while (!wgt_tile_valid_o && timeout > 0) begin
        @(posedge clk);
        timeout--;
      end
      #1;
      $display("  WGT TILE: valid=%0b tag=0x%04h", wgt_tile_valid_o, wgt_tile_tag_o);
      expect_flag("weight tile valid", wgt_tile_valid_o);
      expect_i32("weight tile tag", int'(wgt_tile_tag_o), 16'h0a0a);
    end
  endtask

  task automatic stream_weight_tile_to_array();
    logic [SIZE-1:0] done_seen;
    int timeout;
    begin
      done_seen = '0;
      $display("  WGT LOAD: stream resident tile into WS array");
      @(negedge clk);
      wgt_stream_start_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wgt_stream_start_i = 1'b0;

      timeout = 40;
      while (!wgt_stream_done_o && timeout > 0) begin
        @(posedge clk);
        #1;
        done_seen |= wgt_load_done_o;
        timeout--;
      end

      @(posedge clk);
      #1;
      $display("  WGT LOAD: stream_done=%0b load_done=%b reuse_count=%0d",
               wgt_stream_done_o, done_seen, dbg_weight_reuse_count_o);
      expect_flag("weight stream reached bottom row", done_seen == 2'b11);
      expect_i32("weight reuse count", int'(dbg_weight_reuse_count_o), 1);
    end
  endtask

  task automatic send_activation_req(
      input logic [ACT_ADDR_WIDTH-1:0] addr0,
      input logic [ACT_ADDR_WIDTH-1:0] addr1,
      input logic [TAG_WIDTH-1:0] tag);
    begin
      $display("  ACT REQ: tag=0x%04h addr={row1:%0d,row0:%0d}",
               tag, addr1, addr0);
      @(negedge clk);
      act_req_addr_flatten_i = {addr1, addr0};
      act_req_lane_valid_i = 2'b11;
      act_req_lane_zero_i = 2'b00;
      act_req_tag_i = tag;
      act_req_valid_i = 1'b1;
      do begin
        @(posedge clk);
      end while (!act_req_ready_o);
      @(negedge clk);
      act_req_valid_i = 1'b0;
      act_req_addr_flatten_i = '0;
      act_req_lane_valid_i = '0;
      act_req_lane_zero_i = '0;
      act_req_tag_i = '0;
    end
  endtask

  task automatic capture_psum_pair(
      input int exp_lane0,
      input int exp_lane1);
    int timeout;
    begin
      captured_valid = '0;
      for (int lane = 0; lane < SIZE; lane++) begin
        captured_psum[lane] = '0;
      end

      timeout = 120;
      while (captured_valid != 2'b11 && timeout > 0) begin
        @(posedge clk);
        #1;
        for (int lane = 0; lane < SIZE; lane++) begin
          if (psum_valid_o[lane] && !captured_valid[lane]) begin
            captured_valid[lane] = 1'b1;
            captured_psum[lane] = get_psum(lane);
            $display("  CAPTURE: psum lane%0d = %0d",
                     lane, $signed(get_psum(lane)));
          end
        end
        timeout--;
      end

      expect_flag("captured both psum lanes", captured_valid == 2'b11);
      expect_i32("psum lane0", $signed(captured_psum[0]), exp_lane0);
      expect_i32("psum lane1", $signed(captured_psum[1]), exp_lane1);
    end
  endtask

  initial begin
    init_signals();

    $display("");
    $display("============================================================");
    $display("TEST: MXU V3 weight tile load path");
    $display("============================================================");
    send_weight_tile_req();
    wait_weight_tile_loaded();
    stream_weight_tile_to_array();

    $display("");
    $display("============================================================");
    $display("TEST: MXU V3 activation gather -> skew -> WS SA");
    $display("============================================================");
    send_activation_req(8'd20, 8'd21, 16'h0101);
    capture_psum_pair(38, -54);

    $display("");
    $display("============================================================");
    $display("TEST: MXU V3 reuse active weights for second activation");
    $display("============================================================");
    send_activation_req(8'd22, 8'd23, 16'h0102);
    capture_psum_pair(8, -11);

    expect_i32("activation vectors pushed", int'(dbg_act_vectors_pushed_o), 2);
    expect_i32("activation lane reads", int'(dbg_act_lane_reads_o), 4);
    expect_flag("no PE overflow", overflow_flatten_o == '0);

    $display("");
    $display("DEBUG COUNTERS");
    $display("  act_fetch=%0d act_vectors=%0d act_lane_reads=%0d",
             dbg_act_fetch_cycles_o, dbg_act_vectors_pushed_o, dbg_act_lane_reads_o);
    $display("  wgt_load=%0d wgt_reuse=%0d wgt_empty=%0d wgt_full=%0d",
             dbg_weight_load_cycles_o, dbg_weight_reuse_count_o,
             dbg_weight_buffer_empty_cycles_o, dbg_weight_buffer_full_cycles_o);

    $display("test_mxu_v3_2x2: checks=%0d pass=%0d fail=%0d", checks, passes, fails);
    if (fails != 0) begin
      $fatal(1, "test_mxu_v3_2x2 failed");
    end
    $finish;
  end

endmodule : test_mxu_v3_2x2
