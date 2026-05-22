`timescale 1ns / 1ps

module test_tpu_top_end_to_end;

  localparam int SIZE = 2;
  localparam int DATA_WIDTH = 8;
  localparam int ACC_WIDTH = 32;
  localparam int ACC_DEPTH = 16;
  localparam int ACC_ADDR_WIDTH = $clog2(ACC_DEPTH);
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int REQUANT_MULT_WIDTH = 32;
  localparam int REQUANT_SHIFT_WIDTH = 6;
  localparam int MAX_NUM_TILES = 128;
  localparam int TILE_COUNT_WIDTH = $clog2(MAX_NUM_TILES + 1);
  localparam int UB_BANK_DEPTH = 8192;
  localparam int UB_ADDR_WIDTH = $clog2(UB_BANK_DEPTH);
  localparam int WGT_FIFO_DEPTH = 16;
  localparam int CLK_PERIOD = 10;
  localparam int TIMEOUT_CYCLES = 1200000;

  localparam int INPUT_COUNT = 784;
  localparam int LOGIT_COUNT = 10;
  localparam int MULTI_CASE_COUNT = 4;
  localparam int MAX_FILE_CASES = 256;

  logic clk;
  logic rst_n;

  logic signed [DATA_WIDTH-1:0] input_mem[0:INPUT_COUNT-1];
  logic signed [DATA_WIDTH-1:0] expected_logits[0:LOGIT_COUNT-1];
  logic signed [DATA_WIDTH-1:0] file_input_mem[0:(MAX_FILE_CASES*INPUT_COUNT)-1];
  logic signed [DATA_WIDTH-1:0] file_expected_logits[0:(MAX_FILE_CASES*LOGIT_COUNT)-1];

  logic start_i;
  logic done_o;
  logic busy_o;
  logic error_o;
  logic [4:0] state_o;
  logic [2:0] stage_o;
  logic [15:0] cycle_count_o;
  logic [31:0] error_code_o;

  logic host_rd_en;
  logic host_rd_bank;
  logic [UB_ADDR_WIDTH-1:0] host_rd_addr;
  logic signed [DATA_WIDTH-1:0] host_rd_data;
  logic host_rd_valid;
  logic host_wr_en;
  logic host_wr_bank;
  logic [UB_ADDR_WIDTH-1:0] host_wr_addr;
  logic signed [DATA_WIDTH-1:0] host_wr_data;

  logic overflow_clr;
  logic [SIZE*SIZE-1:0] overflow_flatten;

  logic [4:0] layer_state_o;
  logic [4:0] layer_tile_state_o;
  logic [15:0] layer_spatial_o;
  logic [15:0] layer_oc_tile_o;
  logic [15:0] layer_k_tile_o;
  logic [3:0] pool_state_o;
  logic [15:0] pool_channel_o;
  logic [15:0] pool_row_o;
  logic [15:0] pool_col_o;

  int test_count;
  int pass_count;
  int fail_count;
  int runtime_case_count;
  logic use_file_cases;
  string file_input_hex;
  string file_logits_hex;
  string current_case_name;

  tpu_top #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .WGT_FIFO_DEPTH     (WGT_FIFO_DEPTH),
      .BANK_DEPTH         (UB_BANK_DEPTH),
      .UB_ADDR_WIDTH      (UB_ADDR_WIDTH)
  ) u_tpu_top (
      .clk                   (clk),
      .rst_n                 (rst_n),
      .start_i               (start_i),
      .done_o                (done_o),
      .busy_o                (busy_o),
      .error_o               (error_o),
      .dbg_state_o           (state_o),
      .dbg_stage_o           (stage_o),
      .dbg_cycle_count_o     (cycle_count_o),
      .dbg_error_code_o      (error_code_o),
      .host_rd_en_i          (host_rd_en),
      .host_rd_bank_i        (host_rd_bank),
      .host_rd_addr_i        (host_rd_addr),
      .host_rd_data_o        (host_rd_data),
      .host_rd_valid_o       (host_rd_valid),
      .host_wr_en_i          (host_wr_en),
      .host_wr_bank_i        (host_wr_bank),
      .host_wr_addr_i        (host_wr_addr),
      .host_wr_data_i        (host_wr_data),
      .overflow_clr_i        (overflow_clr),
      .overflow_flatten_o    (overflow_flatten),
      .dbg_layer_state_o     (layer_state_o),
      .dbg_layer_tile_state_o(layer_tile_state_o),
      .dbg_layer_spatial_o   (layer_spatial_o),
      .dbg_layer_oc_tile_o   (layer_oc_tile_o),
      .dbg_layer_k_tile_o    (layer_k_tile_o),
      .dbg_pool_state_o      (pool_state_o),
      .dbg_pool_channel_o    (pool_channel_o),
      .dbg_pool_row_o        (pool_row_o),
      .dbg_pool_col_o        (pool_col_o)
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
    start_i = 1'b0;
    host_rd_en = 1'b0;
    host_rd_bank = 1'b0;
    host_rd_addr = '0;
    host_wr_en = 1'b0;
    host_wr_bank = 1'b0;
    host_wr_addr = '0;
    host_wr_data = '0;
    overflow_clr = 1'b0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    runtime_case_count = MULTI_CASE_COUNT;
    use_file_cases = 1'b0;
    file_input_hex = "";
    file_logits_hex = "";
    current_case_name = "";
  endtask

  task automatic configure_runtime_cases();
    int requested_cases;
    if ($test$plusargs("E2E_FILE_CASES")) begin
      use_file_cases = 1'b1;
      runtime_case_count = MULTI_CASE_COUNT;
      if ($value$plusargs("E2E_CASES=%d", requested_cases)) begin
        runtime_case_count = requested_cases;
      end
      if (!$value$plusargs("E2E_INPUT_HEX=%s", file_input_hex)) begin
        file_input_hex = "../../../CNN_model/python/mnist_classification/18_05/e2e_cases/tpu_top_e2e_inputs_i8.hex";
      end
      if (!$value$plusargs("E2E_LOGITS_HEX=%s", file_logits_hex)) begin
        file_logits_hex = "../../../CNN_model/python/mnist_classification/18_05/e2e_cases/tpu_top_e2e_logits_i8.hex";
      end

      if (runtime_case_count > MAX_FILE_CASES) begin
        $display("  INFO: E2E_CASES=%0d exceeds MAX_FILE_CASES=%0d; clamping",
                 runtime_case_count, MAX_FILE_CASES);
        runtime_case_count = MAX_FILE_CASES;
      end

      $readmemh(file_input_hex, file_input_mem);
      $readmemh(file_logits_hex, file_expected_logits);
      $display("  E2E file cases enabled: cases=%0d", runtime_case_count);
      $display("  inputs = %s", file_input_hex);
      $display("  logits = %s", file_logits_hex);
    end else begin
      use_file_cases = 1'b0;
      runtime_case_count = MULTI_CASE_COUNT;
    end
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
    data = host_rd_data;
    @(negedge clk);
    host_rd_en = 1'b0;
  endtask

  task automatic clear_input_mem();
    for (int idx = 0; idx < INPUT_COUNT; idx++) begin
      input_mem[idx] = '0;
    end
  endtask

  task automatic set_expected_exported_image();
    $readmemh("../../../CNN_model/python/mnist_classification/18_05/final_logits_i8.hex",
              expected_logits);
  endtask

  task automatic set_expected_zero_image();
    expected_logits[0] = -8'sd4;
    expected_logits[1] = 8'sd3;
    expected_logits[2] = 8'sd2;
    expected_logits[3] = -8'sd3;
    expected_logits[4] = -8'sd4;
    expected_logits[5] = 8'sd1;
    expected_logits[6] = -8'sd2;
    expected_logits[7] = 8'sd3;
    expected_logits[8] = 8'sd0;
    expected_logits[9] = -8'sd5;
  endtask

  task automatic set_expected_impulse_center();
    expected_logits[0] = -8'sd12;
    expected_logits[1] = -8'sd3;
    expected_logits[2] = 8'sd3;
    expected_logits[3] = 8'sd3;
    expected_logits[4] = 8'sd0;
    expected_logits[5] = 8'sd2;
    expected_logits[6] = -8'sd5;
    expected_logits[7] = 8'sd0;
    expected_logits[8] = -8'sd2;
    expected_logits[9] = 8'sd0;
  endtask

  task automatic set_expected_checker_pm32();
    expected_logits[0] = -8'sd5;
    expected_logits[1] = 8'sd3;
    expected_logits[2] = 8'sd2;
    expected_logits[3] = -8'sd1;
    expected_logits[4] = -8'sd4;
    expected_logits[5] = 8'sd1;
    expected_logits[6] = -8'sd5;
    expected_logits[7] = 8'sd3;
    expected_logits[8] = -8'sd1;
    expected_logits[9] = -8'sd5;
  endtask

  task automatic configure_case(input int case_idx);
    clear_input_mem();

    if (use_file_cases) begin
      current_case_name = $sformatf("file_case_%0d", case_idx);
      for (int idx = 0; idx < INPUT_COUNT; idx++) begin
        input_mem[idx] = file_input_mem[(case_idx * INPUT_COUNT) + idx];
      end
      for (int idx = 0; idx < LOGIT_COUNT; idx++) begin
        expected_logits[idx] = file_expected_logits[(case_idx * LOGIT_COUNT) + idx];
      end
      return;
    end

    unique case (case_idx)
      0: begin
        current_case_name = "exported_image";
        $readmemh("../../../CNN_model/python/mnist_classification/18_05/input_image_i8.hex",
                  input_mem);
        set_expected_exported_image();
      end

      1: begin
        current_case_name = "zero_image";
        set_expected_zero_image();
      end

      2: begin
        current_case_name = "impulse_center_127";
        input_mem[(14 * 28) + 14] = 8'sd127;
        set_expected_impulse_center();
      end

      3: begin
        current_case_name = "checker_pm32";
        for (int idx = 0; idx < INPUT_COUNT; idx++) begin
          if ((((idx / 28) + (idx % 28)) % 2) == 0) begin
            input_mem[idx] = 8'sd32;
          end else begin
            input_mem[idx] = -8'sd32;
          end
        end
        set_expected_checker_pm32();
      end

      default: begin
        current_case_name = "invalid";
        set_expected_zero_image();
      end
    endcase
  endtask

  task automatic print_expected_logits();
    $display("  expected logits {%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d}",
             $signed(expected_logits[0]), $signed(expected_logits[1]),
             $signed(expected_logits[2]), $signed(expected_logits[3]),
             $signed(expected_logits[4]), $signed(expected_logits[5]),
             $signed(expected_logits[6]), $signed(expected_logits[7]),
             $signed(expected_logits[8]), $signed(expected_logits[9]));
  endtask

  task automatic preload_input_image(input int case_idx);
    print_header("TEST: Host preload input image");
    configure_case(case_idx);

    for (int idx = 0; idx < INPUT_COUNT; idx++) begin
      host_write(1'b0, UB_ADDR_WIDTH'(idx), input_mem[idx]);
    end

    $display("  case[%0d] = %s", case_idx, current_case_name);
    $display("  UB bank0[0:%0d] loaded for current input image", INPUT_COUNT - 1);
    $display("  Full schedule: Conv1 -> Pool1 -> Conv2 -> Pool2 -> FC1 -> FC2");
    print_expected_logits();
  endtask

  task automatic run_top(input int case_idx);
    int cycles;
    logic [2:0] last_stage;

    print_header("TEST: TPU top end-to-end inference");
    $display("  case[%0d] = %s", case_idx, current_case_name);

    @(negedge clk);
    start_i = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    start_i = 1'b0;

    cycles = 0;
    last_stage = 3'd0;
    while (!done_o && !error_o && (cycles < TIMEOUT_CYCLES)) begin
      @(posedge clk);
      #1;
      cycles++;

      if (stage_o != last_stage) begin
        $display("  stage=%0d cycle=%0d layer_state=%0d pool_state=%0d",
                 stage_o, cycles, layer_state_o, pool_state_o);
        last_stage = stage_o;
      end
    end

    $display("  TOP    : done=%b busy=%b error=%b state=%0d stage=%0d cycles=%0d err=0x%08h",
             done_o, busy_o, error_o, state_o, stage_o, cycles, error_code_o);
    $display("  LAYER  : state=%0d tile_state=%0d spatial=%0d oc_tile=%0d k_tile=%0d",
             layer_state_o, layer_tile_state_o, layer_spatial_o,
             layer_oc_tile_o, layer_k_tile_o);
    $display("  POOL   : state=%0d channel=%0d row=%0d col=%0d",
             pool_state_o, pool_channel_o, pool_row_o, pool_col_o);

    expect_flag("top finished", done_o);
    expect_flag("top no error", !error_o);
    expect_flag("datapath no overflow", overflow_flatten == '0);
  endtask

  task automatic check_logits(input int case_idx);
    logic signed [DATA_WIDTH-1:0] actual;
    logic signed [DATA_WIDTH-1:0] actual_logits[0:LOGIT_COUNT-1];
    int mismatch_count;

    print_header("TEST: Host readback final logits");
    $display("  case[%0d] = %s", case_idx, current_case_name);
    mismatch_count = 0;

    for (int idx = 0; idx < LOGIT_COUNT; idx++) begin
      host_read(1'b0, UB_ADDR_WIDTH'(idx), actual);
      actual_logits[idx] = actual;
      test_count++;
      if (actual === expected_logits[idx]) begin
        pass_count++;
      end else begin
        fail_count++;
        mismatch_count++;
        $display("FAIL: logit[%0d] got=%0d expected=%0d",
                 idx, $signed(actual), $signed(expected_logits[idx]));
      end
    end

    $display("  actual logits   {%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d}",
             $signed(actual_logits[0]), $signed(actual_logits[1]),
             $signed(actual_logits[2]), $signed(actual_logits[3]),
             $signed(actual_logits[4]), $signed(actual_logits[5]),
             $signed(actual_logits[6]), $signed(actual_logits[7]),
             $signed(actual_logits[8]), $signed(actual_logits[9]));
    print_expected_logits();
    $display("  mismatches: %0d", mismatch_count);
  endtask

  initial begin
    init_signals();
    configure_runtime_cases();

    for (int case_idx = 0; case_idx < runtime_case_count; case_idx++) begin
      reset_dut();
      preload_input_image(case_idx);
      run_top(case_idx);
      check_logits(case_idx);
    end

    $display("test_tpu_top_end_to_end: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_tpu_top_end_to_end failed");
    end
    $finish;
  end

endmodule : test_tpu_top_end_to_end
