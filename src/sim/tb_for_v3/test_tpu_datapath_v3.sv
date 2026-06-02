`timescale 1ns / 1ps

module test_tpu_datapath_v3;
  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ACT_ADDR_WIDTH = 8;
  localparam int WGT_ADDR_WIDTH = 8;
  localparam int TAG_WIDTH = 16;
  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);
  localparam int NUM_TILES = 2;
  localparam int MAX_NUM_TILES = 128;
  localparam int TILE_COUNT_WIDTH = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1;
  localparam int ACC_WIDTH = 32;
  localparam int ACC_DEPTH = 4;
  localparam int ACC_ADDR_WIDTH = $clog2(ACC_DEPTH);
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int REQUANT_MULT_WIDTH = 32;
  localparam int REQUANT_SHIFT_WIDTH = 6;
  localparam int CLK_PERIOD = 10;
  localparam int MAX_OBSERVE_CYCLES = 140;

  localparam int ACT_RELU = 1;
  localparam logic [1:0] ACT_RELU_MODE = 2'd1;
  localparam int POOL_BYPASS = 0;

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

  logic accumulator_clear_all_i;
  logic accumulator_row_clear_i;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_i;
  logic accumulator_write_en_i;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_i;
  logic accumulator_read_en_i;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_i;

  logic vpu_input_done_i;
  logic [1:0] vpu_act_mode_i;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_i;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_i;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_i;
  logic signed [ACC_WIDTH-1:0] vpu_output_zero_point_i;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_o;
  logic [SIZE-1:0] mxu_psum_valid_o;
  logic [SIZE-1:0] wgt_load_done_o;
  logic psum_packer_busy_o;

  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_o;
  logic accumulator_read_valid_o;
  logic accumulator_row_done_o;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_done_addr_o;
  logic [ACC_DEPTH-1:0] accumulator_row_ready_o;

  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_o;
  logic vpu_data_valid_o;
  logic done_o;

  logic overflow_clr_i;
  logic [SIZE*SIZE-1:0] overflow_flatten_o;

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

  tpu_datapath_v3 #(
      .SIZE                 (SIZE),
      .DATA_WIDTH           (DATA_WIDTH),
      .ACT_ADDR_WIDTH       (ACT_ADDR_WIDTH),
      .WGT_ADDR_WIDTH       (WGT_ADDR_WIDTH),
      .TAG_WIDTH            (TAG_WIDTH),
      .LOCAL_PSUM_WIDTH     (LOCAL_PSUM_WIDTH),
      .MAX_NUM_TILES        (MAX_NUM_TILES),
      .ACC_WIDTH            (ACC_WIDTH),
      .ACC_DEPTH            (ACC_DEPTH),
      .ACC_ADDR_WIDTH       (ACC_ADDR_WIDTH),
      .ACT_WIDTH            (ACC_WIDTH),
      .OUT_WIDTH            (OUT_WIDTH),
      .ACT_MODE             (ACT_RELU),
      .QUANT_ENABLE         (1'b1),
      .BIAS_WIDTH           (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH   (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH  (REQUANT_SHIFT_WIDTH),
      .NORM_SHIFT           (0),
      .NORM_ROUND_ENABLE    (1'b1),
      .POOL_MODE            (POOL_BYPASS),
      .POOL_WINDOW          (2),
      .TILE_COUNT_WIDTH     (TILE_COUNT_WIDTH)
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
      .accumulator_clear_all_i          (accumulator_clear_all_i),
      .accumulator_row_clear_i          (accumulator_row_clear_i),
      .accumulator_row_clear_addr_i     (accumulator_row_clear_addr_i),
      .accumulator_write_en_i           (accumulator_write_en_i),
      .accumulator_write_addr_i         (accumulator_write_addr_i),
      .accumulator_read_en_i            (accumulator_read_en_i),
      .accumulator_read_addr_i          (accumulator_read_addr_i),
      .vpu_input_done_i                 (vpu_input_done_i),
      .vpu_act_mode_i                   (vpu_act_mode_i),
      .vpu_bias_flatten_i               (vpu_bias_flatten_i),
      .vpu_requant_multiplier_flatten_i (vpu_requant_multiplier_flatten_i),
      .vpu_requant_shift_flatten_i      (vpu_requant_shift_flatten_i),
      .vpu_output_zero_point_i          (vpu_output_zero_point_i),
      .mxu_psum_flatten_o               (mxu_psum_flatten_o),
      .mxu_psum_valid_o                 (mxu_psum_valid_o),
      .mxu_valid_mac_count_o            (),
      .psum_packer_busy_o               (psum_packer_busy_o),
      .wgt_load_done_o                  (wgt_load_done_o),
      .accumulator_read_flatten_o       (accumulator_read_flatten_o),
      .accumulator_read_valid_o         (accumulator_read_valid_o),
      .accumulator_row_done_o           (accumulator_row_done_o),
      .accumulator_row_done_addr_o      (accumulator_row_done_addr_o),
      .accumulator_row_ready_o          (accumulator_row_ready_o),
      .vpu_data_flatten_o               (vpu_data_flatten_o),
      .vpu_data_valid_o                 (vpu_data_valid_o),
      .done_o                           (done_o),
      .overflow_clr_i                   (overflow_clr_i),
      .overflow_flatten_o               (overflow_flatten_o),
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
        $display("[%0t] UB RD : addr=%0d data=%0d", $time, ub_rd_addr_o, ub_mem[ub_rd_addr_o]);
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

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_mxu_psum(input int lane);
    get_mxu_psum = mxu_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_packed_psum(input int lane);
    get_packed_psum =
        dut.u_psum_packer.packed_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] get_acc_lane(input int lane);
    get_acc_lane = accumulator_read_flatten_o[(lane*ACC_WIDTH)+:ACC_WIDTH];
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] get_vpu_lane(input int lane);
    get_vpu_lane = vpu_data_flatten_o[(lane*OUT_WIDTH)+:OUT_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] extend_psum(
      input logic signed [LOCAL_PSUM_WIDTH-1:0] value_i);
    extend_psum = {{(ACC_WIDTH - LOCAL_PSUM_WIDTH) {value_i[LOCAL_PSUM_WIDTH-1]}}, value_i};
  endfunction

  task automatic print_header(input string title);
    $display("");
    $display("============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

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
      accumulator_clear_all_i = 1'b0;
      accumulator_row_clear_i = 1'b0;
      accumulator_row_clear_addr_i = '0;
      accumulator_write_en_i = 1'b0;
      accumulator_write_addr_i = '0;
      accumulator_read_en_i = 1'b0;
      accumulator_read_addr_i = '0;
      vpu_input_done_i = 1'b0;
      vpu_act_mode_i = ACT_RELU_MODE;
      vpu_bias_flatten_i = {32'sd5, 32'sd4};
      vpu_requant_multiplier_flatten_i = {32'sd16, 32'sd16};
      vpu_requant_shift_flatten_i = {6'd4, 6'd4};
      vpu_output_zero_point_i = 32'sd0;
      overflow_clr_i = 1'b0;
      checks = 0;
      passes = 0;
      fails = 0;

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

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic send_weight_tile_req();
    begin
      print_header("TEST: TPU datapath V3 weight tile load");
      $display("  WGT REQ: W=[[2,-3],[5,-7]]");
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

  task automatic wait_weight_tile_loaded_and_stream();
    logic [SIZE-1:0] done_seen;
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

      done_seen = '0;
      @(negedge clk);
      wgt_stream_start_i = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wgt_stream_start_i = 1'b0;

      for (int cycle = 0; cycle < 40; cycle++) begin
        @(posedge clk);
        #1;
        done_seen |= wgt_load_done_o;
      end

      $display("  WGT LOAD: load_done=%b reuse_count=%0d",
               done_seen, dbg_weight_reuse_count_o);
      expect_flag("weight stream reached both bottom PEs", done_seen == 2'b11);
    end
  endtask

  task automatic send_activation_req(
      input logic [ACT_ADDR_WIDTH-1:0] addr0,
      input logic [ACT_ADDR_WIDTH-1:0] addr1,
      input logic [TAG_WIDTH-1:0] tag);
    begin
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

  task automatic run_activation_tile(
      input logic [ACT_ADDR_WIDTH-1:0] addr0,
      input logic [ACT_ADDR_WIDTH-1:0] addr1,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected_lane0,
      input logic signed [LOCAL_PSUM_WIDTH-1:0] expected_lane1,
      input int tile_idx);
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] captured_lane1;
    logic [SIZE-1:0] seen;
    logic packed_seen;
    begin
      captured_lane0 = '0;
      captured_lane1 = '0;
      seen = '0;
      packed_seen = 1'b0;

      @(negedge clk);
      accumulator_write_addr_i = '0;
      accumulator_write_en_i = 1'b1;
      send_activation_req(addr0, addr1, TAG_WIDTH'(16'h1000 + tile_idx));
      $display("  launch activation tile%0d addr={row1:%0d,row0:%0d}", tile_idx, addr1, addr0);

      for (int cycle = 0; cycle < MAX_OBSERVE_CYCLES; cycle++) begin
        @(posedge clk);
        #1;

        if (mxu_psum_valid_o[0] && !seen[0]) begin
          seen[0] = 1'b1;
          captured_lane0 = get_mxu_psum(0);
          $display("  CAPTURE: MXU psum lane0 = %0d", $signed(captured_lane0));
        end

        if (mxu_psum_valid_o[1] && !seen[1]) begin
          seen[1] = 1'b1;
          captured_lane1 = get_mxu_psum(1);
          $display("  CAPTURE: MXU psum lane1 = %0d", $signed(captured_lane1));
        end

        if (dut.u_psum_packer.packed_valid_o && !packed_seen) begin
          packed_seen = 1'b1;
          $display("  PACKED : tile%0d row0 psum={lane1:%0d,lane0:%0d}",
                   tile_idx, $signed(get_packed_psum(1)), $signed(get_packed_psum(0)));
          expect_i32($sformatf("tile%0d packed lane0", tile_idx),
                     $signed(get_packed_psum(0)), $signed(expected_lane0));
          expect_i32($sformatf("tile%0d packed lane1", tile_idx),
                     $signed(get_packed_psum(1)), $signed(expected_lane1));
          break;
        end
      end

      expect_flag($sformatf("tile%0d MXU produced both psum lanes", tile_idx), seen == 2'b11);
      expect_flag($sformatf("tile%0d packer produced one vector", tile_idx), packed_seen);
      expect_i32($sformatf("tile%0d MXU lane0 psum", tile_idx),
                 $signed(captured_lane0), $signed(expected_lane0));
      expect_i32($sformatf("tile%0d MXU lane1 psum", tile_idx),
                 $signed(captured_lane1), $signed(expected_lane1));

      @(negedge clk);
      accumulator_write_en_i = 1'b0;
      @(posedge clk);
      #1;
      $display("  ACC WRITE: tile%0d row_done=%b ready=%b",
               tile_idx, accumulator_row_done_o, accumulator_row_ready_o[0]);
    end
  endtask

  task automatic read_accumulator_to_vpu();
    begin
      print_header("TEST: Accumulator read -> VPU");
      @(negedge clk);
      accumulator_read_addr_i = '0;
      accumulator_read_en_i = 1'b1;
      vpu_input_done_i = 1'b1;
      @(posedge clk);
      #1;
      $display("  ACC READ: valid=%b row0={lane1:%0d,lane0:%0d}",
               accumulator_read_valid_o, $signed(get_acc_lane(1)), $signed(get_acc_lane(0)));
      expect_flag("accumulator read valid", accumulator_read_valid_o);
      @(negedge clk);
      accumulator_read_en_i = 1'b0;
    end
  endtask

  task automatic wait_vpu_output();
    begin
      for (int cycle = 0; cycle < 40; cycle++) begin
        @(posedge clk);
        #1;
        if (vpu_data_valid_o) begin
          $display("  VPU OUT : data={lane1:%0d,lane0:%0d} done=%b",
                   $signed(get_vpu_lane(1)), $signed(get_vpu_lane(0)), done_o);
          expect_flag("VPU output valid", 1'b1);
          return;
        end
      end

      expect_flag("VPU output valid", 1'b0);
    end
  endtask

  task automatic test_full_datapath();
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile0_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile0_lane1;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile1_lane0;
    logic signed [LOCAL_PSUM_WIDTH-1:0] tile1_lane1;
    logic signed [ACC_WIDTH-1:0] expected_acc0;
    logic signed [ACC_WIDTH-1:0] expected_acc1;
    begin
      print_header("TEST: MXU V3 -> psum packer -> accumulator");

      tile0_lane0 = (8'sd4 * 8'sd2) + (8'sd6 * 8'sd5);
      tile0_lane1 = (8'sd4 * -8'sd3) + (8'sd6 * -8'sd7);
      tile1_lane0 = (-8'sd1 * 8'sd2) + (8'sd2 * 8'sd5);
      tile1_lane1 = (-8'sd1 * -8'sd3) + (8'sd2 * -8'sd7);

      expected_acc0 = extend_psum(tile0_lane0) + extend_psum(tile1_lane0);
      expected_acc1 = extend_psum(tile0_lane1) + extend_psum(tile1_lane1);

      run_activation_tile(8'd20, 8'd21, tile0_lane0, tile0_lane1, 0);
      expect_flag("accumulator row not ready after first tile", accumulator_row_ready_o[0] == 1'b0);

      run_activation_tile(8'd22, 8'd23, tile1_lane0, tile1_lane1, 1);
      expect_flag("accumulator row_done after second tile", accumulator_row_done_o);
      expect_flag("accumulator row 0 ready", accumulator_row_ready_o[0]);
      expect_flag("no PE overflow in V3 datapath test", overflow_flatten_o == '0);

      read_accumulator_to_vpu();
      expect_i32("accumulator lane0 sum", $signed(get_acc_lane(0)), $signed(expected_acc0));
      expect_i32("accumulator lane1 sum", $signed(get_acc_lane(1)), $signed(expected_acc1));

      wait_vpu_output();
      expect_i32("VPU lane0 bias + requant", $signed(get_vpu_lane(0)), 50);
      expect_i32("VPU lane1 bias + requant then ReLU", $signed(get_vpu_lane(1)), 0);
      expect_flag("VPU done follows final row", done_o);
    end
  endtask

  initial begin
    init_signals();

    send_weight_tile_req();
    wait_weight_tile_loaded_and_stream();
    test_full_datapath();

    expect_i32("activation vectors pushed", int'(dbg_act_vectors_pushed_o), 2);
    expect_i32("activation lane reads", int'(dbg_act_lane_reads_o), 4);
    expect_i32("weight reuse count", int'(dbg_weight_reuse_count_o), 1);

    $display("");
    $display("DEBUG COUNTERS");
    $display("  act_fetch=%0d act_vectors=%0d act_lane_reads=%0d",
             dbg_act_fetch_cycles_o, dbg_act_vectors_pushed_o, dbg_act_lane_reads_o);
    $display("  wgt_load=%0d wgt_reuse=%0d wgt_empty=%0d wgt_full=%0d",
             dbg_weight_load_cycles_o, dbg_weight_reuse_count_o,
             dbg_weight_buffer_empty_cycles_o, dbg_weight_buffer_full_cycles_o);

    $display("test_tpu_datapath_v3: checks=%0d pass=%0d fail=%0d", checks, passes, fails);
    if (fails != 0) begin
      $fatal(1, "test_tpu_datapath_v3 failed");
    end
    $finish;
  end

endmodule : test_tpu_datapath_v3
