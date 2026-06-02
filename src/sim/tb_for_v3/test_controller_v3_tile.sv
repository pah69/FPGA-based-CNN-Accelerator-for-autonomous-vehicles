`timescale 1ns / 1ps

module test_controller_v3_tile;
  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ADDR_WIDTH = 8;
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
  localparam int MAX_RUN_CYCLES = 500;

  localparam logic [1:0] LAYER_FC = 2'd1;
  localparam int ACT_RELU = 1;
  localparam logic [1:0] ACT_RELU_MODE = 2'd1;
  localparam int POOL_BYPASS = 0;

  logic clk;
  logic rst_n;
  logic start_i;
  logic clear_i;

  logic ctrl_done_o;
  logic ctrl_busy_o;
  logic ctrl_error_o;
  logic [4:0] ctrl_dbg_state_o;
  logic [15:0] ctrl_dbg_k_tile_o;
  logic [31:0] ctrl_dbg_cycle_count_o;
  logic [31:0] ctrl_dbg_error_code_o;

  logic wgt_req_valid_w;
  logic wgt_req_ready_w;
  logic [SIZE*SIZE*ADDR_WIDTH-1:0] wgt_req_addr_flatten_w;
  logic [SIZE*SIZE-1:0] wgt_req_valid_mask_w;
  logic [SIZE*SIZE-1:0] wgt_req_zero_mask_w;
  logic [TAG_WIDTH-1:0] wgt_req_tag_w;
  logic wgt_tile_release_w;
  logic wgt_stream_start_w;
  logic wgt_tile_valid_w;
  logic [SIZE-1:0] wgt_load_done_w;

  logic act_req_valid_w;
  logic act_req_ready_w;
  logic [SIZE*ADDR_WIDTH-1:0] act_req_addr_flatten_w;
  logic [SIZE-1:0] act_req_lane_valid_w;
  logic [SIZE-1:0] act_req_lane_zero_w;
  logic [TAG_WIDTH-1:0] act_req_tag_w;
  logic act_launch_ready_w;
  logic act_launch_w;

  logic clear_dp_i;
  logic compute_enable_i;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_i;

  logic ub_rd_en_o;
  logic [ADDR_WIDTH-1:0] ub_rd_addr_o;
  logic signed [DATA_WIDTH-1:0] ub_rd_data_i;
  logic ub_rd_valid_i;

  logic weight_rd_en_o;
  logic [ADDR_WIDTH-1:0] weight_rd_addr_o;
  logic signed [DATA_WIDTH-1:0] weight_rd_data_i;
  logic weight_rd_valid_i;

  logic accumulator_clear_all_w;
  logic accumulator_row_clear_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_w;
  logic accumulator_write_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_w;
  logic accumulator_read_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_w;

  logic vpu_input_done_w;
  logic [1:0] vpu_act_mode_w;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_w;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_w;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_w;
  logic signed [ACC_WIDTH-1:0] vpu_output_zero_point_w;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_o;
  logic [SIZE-1:0] mxu_psum_valid_o;
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

  logic signed [DATA_WIDTH-1:0] ub_mem[0:(1<<ADDR_WIDTH)-1];
  logic signed [DATA_WIDTH-1:0] weight_mem[0:(1<<ADDR_WIDTH)-1];

  int checks;
  int passes;
  int fails;
  int wgt_req_count;
  int act_req_count;
  logic seen_ctrl_done;
  logic seen_vpu_output;

  tpu_controller_v3_tile #(
      .SIZE               (SIZE),
      .ACT_ADDR_WIDTH     (ADDR_WIDTH),
      .WGT_ADDR_WIDTH     (ADDR_WIDTH),
      .TAG_WIDTH          (TAG_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH)
  ) u_controller (
      .clk                                (clk),
      .rst_n                              (rst_n),
      .start_i                            (start_i),
      .clear_i                            (clear_i),
      .done_o                             (ctrl_done_o),
      .busy_o                             (ctrl_busy_o),
      .error_o                            (ctrl_error_o),
      .dbg_state_o                        (ctrl_dbg_state_o),
      .dbg_k_tile_o                       (ctrl_dbg_k_tile_o),
      .dbg_cycle_count_o                  (ctrl_dbg_cycle_count_o),
      .dbg_error_code_o                   (ctrl_dbg_error_code_o),
      .layer_type_i                       (LAYER_FC),
      .activation_base_addr_i             (8'd20),
      .weight_base_addr_i                 (8'd10),
      .in_h_i                             (16'd0),
      .in_w_i                             (16'd0),
      .out_w_i                            (16'd0),
      .out_ch_i                           (16'd16),
      .kernel_h_i                         (16'd0),
      .kernel_w_i                         (16'd0),
      .k_total_i                          (16'd4),
      .num_k_tiles_i                      (16'd2),
      .spatial_idx_i                      (16'd0),
      .oc_tile_idx_i                      (16'd0),
      .accumulator_row_addr_i             ('0),
      .wgt_req_valid_o                    (wgt_req_valid_w),
      .wgt_req_ready_i                    (wgt_req_ready_w),
      .wgt_req_addr_flatten_o             (wgt_req_addr_flatten_w),
      .wgt_req_valid_mask_o               (wgt_req_valid_mask_w),
      .wgt_req_zero_mask_o                (wgt_req_zero_mask_w),
      .wgt_req_tag_o                      (wgt_req_tag_w),
      .wgt_tile_release_o                 (wgt_tile_release_w),
      .wgt_stream_start_o                 (wgt_stream_start_w),
      .wgt_tile_valid_i                   (wgt_tile_valid_w),
      .wgt_load_done_i                    (wgt_load_done_w),
      .act_req_valid_o                    (act_req_valid_w),
      .act_req_ready_i                    (act_req_ready_w),
      .act_req_addr_flatten_o             (act_req_addr_flatten_w),
      .act_req_lane_valid_o               (act_req_lane_valid_w),
      .act_req_lane_zero_o                (act_req_lane_zero_w),
      .act_req_tag_o                      (act_req_tag_w),
      .act_launch_ready_i                 (act_launch_ready_w),
      .act_launch_o                       (act_launch_w),
      .accumulator_clear_all_o            (accumulator_clear_all_w),
      .accumulator_row_clear_o            (accumulator_row_clear_w),
      .accumulator_row_clear_addr_o       (accumulator_row_clear_addr_w),
      .accumulator_write_en_o             (accumulator_write_en_w),
      .accumulator_write_addr_o           (accumulator_write_addr_w),
      .accumulator_read_en_o              (accumulator_read_en_w),
      .accumulator_read_addr_o            (accumulator_read_addr_w),
      .accumulator_read_valid_i           (accumulator_read_valid_o),
      .accumulator_row_ready_i            (accumulator_row_ready_o),
      .vpu_input_done_o                   (vpu_input_done_w),
      .vpu_act_mode_o                     (vpu_act_mode_w),
      .vpu_bias_flatten_o                 (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_o   (vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_o        (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_o            (vpu_output_zero_point_w),
      .vpu_data_valid_i                   (vpu_data_valid_o),
      .mxu_psum_valid_i                   (mxu_psum_valid_o),
      .psum_packer_busy_i                 (psum_packer_busy_o),
      .vpu_act_mode_i                     (ACT_RELU_MODE),
      .vpu_bias_flatten_i                 ({32'sd5, 32'sd4}),
      .vpu_requant_multiplier_flatten_i   ({32'sd16, 32'sd16}),
      .vpu_requant_shift_flatten_i        ({6'd4, 6'd4}),
      .vpu_output_zero_point_i            (32'sd0)
  );

  tpu_datapath_v3 #(
      .SIZE                 (SIZE),
      .DATA_WIDTH           (DATA_WIDTH),
      .ACT_ADDR_WIDTH       (ADDR_WIDTH),
      .WGT_ADDR_WIDTH       (ADDR_WIDTH),
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
      .GATED_ACT_LAUNCH     (1'b1),
      .TILE_COUNT_WIDTH     (TILE_COUNT_WIDTH)
  ) u_datapath (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .clear_i                          (clear_dp_i),
      .compute_enable_i                 (compute_enable_i),
      .num_tiles_i                      (num_tiles_i),
      .act_req_valid_i                  (act_req_valid_w),
      .act_req_ready_o                  (act_req_ready_w),
      .act_req_addr_flatten_i           (act_req_addr_flatten_w),
      .act_req_lane_valid_i             (act_req_lane_valid_w),
      .act_req_lane_zero_i              (act_req_lane_zero_w),
      .act_req_tag_i                    (act_req_tag_w),
      .act_launch_i                     (act_launch_w),
      .act_launch_ready_o               (act_launch_ready_w),
      .ub_rd_en_o                       (ub_rd_en_o),
      .ub_rd_addr_o                     (ub_rd_addr_o),
      .ub_rd_data_i                     (ub_rd_data_i),
      .ub_rd_valid_i                    (ub_rd_valid_i),
      .wgt_req_valid_i                  (wgt_req_valid_w),
      .wgt_req_ready_o                  (wgt_req_ready_w),
      .wgt_req_addr_flatten_i           (wgt_req_addr_flatten_w),
      .wgt_req_valid_mask_i             (wgt_req_valid_mask_w),
      .wgt_req_zero_mask_i              (wgt_req_zero_mask_w),
      .wgt_req_tag_i                    (wgt_req_tag_w),
      .wgt_tile_release_i               (wgt_tile_release_w),
      .wgt_stream_start_i               (wgt_stream_start_w),
      .wgt_stream_ready_o               (),
      .wgt_tile_valid_o                 (wgt_tile_valid_w),
      .wgt_tile_tag_o                   (),
      .wgt_stream_done_o                (),
      .weight_rd_en_o                   (weight_rd_en_o),
      .weight_rd_addr_o                 (weight_rd_addr_o),
      .weight_rd_data_i                 (weight_rd_data_i),
      .weight_rd_valid_i                (weight_rd_valid_i),
      .accumulator_clear_all_i          (accumulator_clear_all_w),
      .accumulator_row_clear_i          (accumulator_row_clear_w),
      .accumulator_row_clear_addr_i     (accumulator_row_clear_addr_w),
      .accumulator_write_en_i           (accumulator_write_en_w),
      .accumulator_write_addr_i         (accumulator_write_addr_w),
      .accumulator_read_en_i            (accumulator_read_en_w),
      .accumulator_read_addr_i          (accumulator_read_addr_w),
      .vpu_input_done_i                 (vpu_input_done_w),
      .vpu_act_mode_i                   (vpu_act_mode_w),
      .vpu_bias_flatten_i               (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_i (vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_i      (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_i          (vpu_output_zero_point_w),
      .mxu_psum_flatten_o               (mxu_psum_flatten_o),
      .mxu_psum_valid_o                 (mxu_psum_valid_o),
      .mxu_valid_mac_count_o            (),
      .psum_packer_busy_o               (psum_packer_busy_o),
      .wgt_load_done_o                  (wgt_load_done_w),
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

  function automatic logic [ADDR_WIDTH-1:0] act_req_addr(input int lane);
    act_req_addr = act_req_addr_flatten_w[(lane*ADDR_WIDTH)+:ADDR_WIDTH];
  endfunction

  function automatic logic [ADDR_WIDTH-1:0] wgt_req_addr(input int lane, input int col);
    wgt_req_addr = wgt_req_addr_flatten_w[(((lane*SIZE)+col)*ADDR_WIDTH)+:ADDR_WIDTH];
  endfunction

  function automatic logic signed [LOCAL_PSUM_WIDTH-1:0] get_mxu_psum(input int lane);
    get_mxu_psum = mxu_psum_flatten_o[(lane*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH];
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] get_acc_lane(input int lane);
    get_acc_lane = accumulator_read_flatten_o[(lane*ACC_WIDTH)+:ACC_WIDTH];
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] get_vpu_lane(input int lane);
    get_vpu_lane = vpu_data_flatten_o[(lane*OUT_WIDTH)+:OUT_WIDTH];
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
      start_i = 1'b0;
      clear_i = 1'b0;
      clear_dp_i = 1'b0;
      compute_enable_i = 1'b1;
      num_tiles_i = TILE_COUNT_WIDTH'(NUM_TILES);
      overflow_clr_i = 1'b0;
      checks = 0;
      passes = 0;
      fails = 0;
      wgt_req_count = 0;
      act_req_count = 0;
      seen_ctrl_done = 1'b0;
      seen_vpu_output = 1'b0;

      for (int idx = 0; idx < (1 << ADDR_WIDTH); idx++) begin
        ub_mem[idx] = '0;
        weight_mem[idx] = '0;
      end

      ub_mem[20] = 8'sd4;
      ub_mem[21] = 8'sd6;
      ub_mem[22] = -8'sd1;
      ub_mem[23] = 8'sd2;

      weight_mem[10] = 8'sd2;
      weight_mem[11] = -8'sd3;
      weight_mem[26] = 8'sd5;
      weight_mem[27] = -8'sd7;
      weight_mem[42] = 8'sd2;
      weight_mem[43] = -8'sd3;
      weight_mem[58] = 8'sd5;
      weight_mem[59] = -8'sd7;

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic check_weight_req(input int req_idx);
    begin
      if (req_idx == 0) begin
        expect_i32("k_tile0 weight r0c0 addr", wgt_req_addr(0, 0), 10);
        expect_i32("k_tile0 weight r0c1 addr", wgt_req_addr(0, 1), 11);
        expect_i32("k_tile0 weight r1c0 addr", wgt_req_addr(1, 0), 26);
        expect_i32("k_tile0 weight r1c1 addr", wgt_req_addr(1, 1), 27);
      end else if (req_idx == 1) begin
        expect_i32("k_tile1 weight r0c0 addr", wgt_req_addr(0, 0), 42);
        expect_i32("k_tile1 weight r0c1 addr", wgt_req_addr(0, 1), 43);
        expect_i32("k_tile1 weight r1c0 addr", wgt_req_addr(1, 0), 58);
        expect_i32("k_tile1 weight r1c1 addr", wgt_req_addr(1, 1), 59);
      end
      expect_flag($sformatf("k_tile%0d weight valid mask", req_idx), wgt_req_valid_mask_w == 4'b1111);
      expect_flag($sformatf("k_tile%0d weight zero mask", req_idx), wgt_req_zero_mask_w == 4'b0000);
    end
  endtask

  task automatic check_activation_req(input int req_idx);
    begin
      if (req_idx == 0) begin
        expect_i32("k_tile0 act lane0 addr", act_req_addr(0), 20);
        expect_i32("k_tile0 act lane1 addr", act_req_addr(1), 21);
      end else if (req_idx == 1) begin
        expect_i32("k_tile1 act lane0 addr", act_req_addr(0), 22);
        expect_i32("k_tile1 act lane1 addr", act_req_addr(1), 23);
      end
      expect_flag($sformatf("k_tile%0d act valid mask", req_idx), act_req_lane_valid_w == 2'b11);
      expect_flag($sformatf("k_tile%0d act zero mask", req_idx), act_req_lane_zero_w == 2'b00);
    end
  endtask

  initial begin
    init_signals();

    print_header("TEST: V3 tile controller -> TPU datapath");
    @(negedge clk);
    start_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start_i = 1'b0;

    for (int cycle = 0; cycle < MAX_RUN_CYCLES; cycle++) begin
      @(posedge clk);
      #1;

      if (wgt_req_valid_w && wgt_req_ready_w) begin
        $display("  WGT REQ[%0d]: req_k_tile=%0d active_k_tile=%0d addr={{r1c1:%0d,r1c0:%0d},{r0c1:%0d,r0c0:%0d}}",
                 wgt_req_count, int'(wgt_req_tag_w - 16'h3000), ctrl_dbg_k_tile_o,
                 wgt_req_addr(1, 1), wgt_req_addr(1, 0),
                 wgt_req_addr(0, 1), wgt_req_addr(0, 0));
        check_weight_req(wgt_req_count);
        wgt_req_count++;
      end

      if (wgt_tile_valid_w && ctrl_dbg_state_o == 5'd3) begin
        $display("  WGT TILE: k_tile=%0d valid=1", ctrl_dbg_k_tile_o);
      end

      if (wgt_stream_start_w) begin
        $display("  WGT STREAM START: k_tile=%0d", ctrl_dbg_k_tile_o);
      end

      if (act_req_valid_w && act_req_ready_w) begin
        $display("  ACT REQ[%0d]: k_tile=%0d addr={lane1:%0d,lane0:%0d}",
                 act_req_count, int'(act_req_tag_w - 16'h4000), act_req_addr(1), act_req_addr(0));
        check_activation_req(act_req_count);
        act_req_count++;
      end

      if (act_launch_w && act_launch_ready_w) begin
        $display("  ACT LAUNCH: k_tile=%0d", ctrl_dbg_k_tile_o);
      end

      if (mxu_psum_valid_o[0]) begin
        $display("  CAPTURE: k_tile=%0d MXU psum lane0=%0d",
                 ctrl_dbg_k_tile_o, $signed(get_mxu_psum(0)));
      end

      if (mxu_psum_valid_o[1]) begin
        $display("  CAPTURE: k_tile=%0d MXU psum lane1=%0d",
                 ctrl_dbg_k_tile_o, $signed(get_mxu_psum(1)));
      end

      if (accumulator_row_done_o) begin
        $display("  ACC DONE: row=%0d ready=%b",
                 accumulator_row_done_addr_o, accumulator_row_ready_o[0]);
      end

      if (accumulator_read_valid_o) begin
        $display("  ACC READ: row0={lane1:%0d,lane0:%0d}",
                 $signed(get_acc_lane(1)), $signed(get_acc_lane(0)));
        expect_i32("accumulator lane0 sum", $signed(get_acc_lane(0)), 46);
        expect_i32("accumulator lane1 sum", $signed(get_acc_lane(1)), -65);
      end

      if (vpu_data_valid_o && !seen_vpu_output) begin
        seen_vpu_output = 1'b1;
        $display("  VPU OUT : data={lane1:%0d,lane0:%0d} done=%b",
                 $signed(get_vpu_lane(1)), $signed(get_vpu_lane(0)), done_o);
        expect_i32("VPU lane0 bias + requant", $signed(get_vpu_lane(0)), 50);
        expect_i32("VPU lane1 bias + requant then ReLU", $signed(get_vpu_lane(1)), 0);
      end

      if (ctrl_done_o) begin
        seen_ctrl_done = 1'b1;
        $display("  CTRL DONE: cycles=%0d state=%0d error=%0b err=0x%08h",
                 ctrl_dbg_cycle_count_o, ctrl_dbg_state_o, ctrl_error_o, ctrl_dbg_error_code_o);
        break;
      end

      if (ctrl_error_o) begin
        $display("  CTRL ERROR: state=%0d err=0x%08h", ctrl_dbg_state_o, ctrl_dbg_error_code_o);
        break;
      end
    end

    expect_flag("controller completed", seen_ctrl_done);
    expect_flag("controller did not report error", !ctrl_error_o);
    expect_flag("VPU output observed", seen_vpu_output);
    expect_i32("weight request count", wgt_req_count, 2);
    expect_i32("activation request count", act_req_count, 2);
    expect_i32("activation vectors pushed", int'(dbg_act_vectors_pushed_o), 2);
    expect_i32("activation lane reads", int'(dbg_act_lane_reads_o), 4);
    expect_i32("weight reuse count", int'(dbg_weight_reuse_count_o), 2);

    $display("");
    $display("DEBUG COUNTERS");
    $display("  ctrl_cycles=%0d final_state=%0d final_k_tile=%0d",
             ctrl_dbg_cycle_count_o, ctrl_dbg_state_o, ctrl_dbg_k_tile_o);
    $display("  act_fetch=%0d act_vectors=%0d act_lane_reads=%0d",
             dbg_act_fetch_cycles_o, dbg_act_vectors_pushed_o, dbg_act_lane_reads_o);
    $display("  wgt_load=%0d wgt_reuse=%0d wgt_empty=%0d wgt_full=%0d",
             dbg_weight_load_cycles_o, dbg_weight_reuse_count_o,
             dbg_weight_buffer_empty_cycles_o, dbg_weight_buffer_full_cycles_o);

    $display("test_controller_v3_tile: checks=%0d pass=%0d fail=%0d", checks, passes, fails);
    if (fails != 0) begin
      $fatal(1, "test_controller_v3_tile failed");
    end
    $finish;
  end

endmodule : test_controller_v3_tile
