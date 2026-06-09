`timescale 1ns / 1ps

module test_tpu_top_end_to_end;

`ifndef TPU_SIZE
`define TPU_SIZE 4
`endif

`ifndef TPU_ACC_DEPTH
`define TPU_ACC_DEPTH 16
`endif

  localparam int SIZE = `TPU_SIZE;
  localparam int DATA_WIDTH = 8;
  localparam int ACC_WIDTH = 32;
  localparam int ACC_DEPTH = `TPU_ACC_DEPTH;
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
  localparam int KLOOP_STATE_COUNT = 17;
  localparam int PREFETCH_COUNTER_COUNT = 33;
  localparam bit DEFAULT_PRINT_EXPECTED_LOGITS = 1'b0;
  localparam bit DEFAULT_PRINT_RESULT_LOGITS = 1'b0;
  localparam bit DEFAULT_PRINT_STAGE_TRANSITIONS = 1'b0;
  localparam bit DEFAULT_PRINT_STATE_SNAPSHOTS = 1'b0;
  localparam bit DEFAULT_PRINT_PHASE_MAC_COUNTERS = 1'b0;
  localparam bit DEFAULT_PRINT_DRAIN_COUNTERS = 1'b0;
  localparam bit DEFAULT_PRINT_PACKER_COUNTERS = 1'b0;
  localparam bit DEFAULT_PRINT_KLOOP_STATE_COUNTERS = 1'b0;
  localparam bit DEFAULT_PRINT_PREFETCH_COUNTERS = 1'b0;
  localparam int LOGIT_PRINT_CASE_LIMIT = 4;

  localparam int KLOOP_S_CLEAR_ACC_BLOCK = 1;
  localparam int KLOOP_S_FETCH_ROM = 2;
  localparam int KLOOP_S_WAIT_ROM = 3;
  localparam int KLOOP_S_WRITE_WEIGHT_ROW = 4;
  localparam int KLOOP_S_START_WEIGHT_LOAD = 5;
  localparam int KLOOP_S_WAIT_WEIGHT_LOAD = 6;
  localparam int KLOOP_S_READ_ACT_REQ = 7;
  localparam int KLOOP_S_READ_ACT_WAIT = 8;
  localparam int KLOOP_S_LAUNCH_ACT = 9;
  localparam int KLOOP_S_DRAIN_MXU = 10;
  localparam int KLOOP_S_WAIT_ACC_READY = 11;
  localparam int KLOOP_S_READ_ACC_ROW = 12;
  localparam int KLOOP_S_WAIT_VPU_OUTPUT = 13;
  localparam int KLOOP_S_WRITE_OUTPUT_LANE = 14;

  localparam int PREFETCH_ATTEMPTS = 0;
  localparam int PREFETCH_PUSHES = 1;
  localparam int PREFETCH_HITS = 2;
  localparam int PREFETCH_MISSES = 3;
  localparam int PREFETCH_DROPS_FULL = 4;
  localparam int PREFETCH_INVALIDATED_BOUNDARY = 5;
  localparam int PREFETCH_QUEUE_FULL_CYCLES = 6;
  localparam int PREFETCH_QUEUE_EMPTY_ON_NEED = 7;
  localparam int PREFETCH_MAX_OCCUPANCY = 8;
  localparam int PREFETCH_OCCUPANCY_SUM = 9;
  localparam int PREFETCH_OCCUPANCY_SAMPLES = 10;
  localparam int PREFETCH_CURRENT_OCCUPANCY = 11;
  localparam int PREFETCH_EARLY_ATTEMPTS = 12;
  localparam int PREFETCH_EARLY_PUSHES = 13;
  localparam int PREFETCH_DRAIN_ATTEMPTS = 14;
  localparam int PREFETCH_DRAIN_PUSHES = 15;
  localparam int PREFETCH_STALL_QUEUE_FULL = 16;
  localparam int PREFETCH_STALL_UB_BUSY = 17;
  localparam int PREFETCH_STALL_NO_CANDIDATE = 18;
  localparam int PREFETCH_MISS_NO_ENTRY = 19;
  localparam int PREFETCH_MISS_TAG_MISMATCH = 20;
  localparam int PREFETCH_MISS_LANE_INCOMPLETE = 21;
  localparam int PREFETCH_MISS_INVALID_BOUNDARY = 22;
  localparam int PREFETCH_MISS_WRONG_K_TILE = 23;
  localparam int PREFETCH_MISS_WRONG_SPATIAL = 24;
  localparam int PREFETCH_MISS_WRONG_OC_TILE = 25;
  localparam int PREFETCH_VECTOR_START = 26;
  localparam int PREFETCH_VECTOR_PUSH = 27;
  localparam int PREFETCH_LANE_REQ = 28;
  localparam int PREFETCH_LANE_CAPTURE = 29;
  localparam int PREFETCH_ISSUE_CYCLES = 30;
  localparam int PREFETCH_BUBBLE_CYCLES = 31;
  localparam int PREFETCH_BUSY_CYCLES = 32;

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
  logic [31:0] cycle_count_o;
  logic [31:0] conv1_cycle_count_o;
  logic [31:0] pool1_cycle_count_o;
  logic [31:0] conv2_cycle_count_o;
  logic [31:0] pool2_cycle_count_o;
  logic [31:0] fc1_cycle_count_o;
  logic [31:0] fc2_cycle_count_o;
  logic [31:0] conv1_weight_load_cycles_o;
  logic [31:0] conv1_activation_fetch_cycles_o;
  logic [31:0] conv1_mxu_active_cycles_o;
  logic [31:0] conv1_mxu_drain_cycles_o;
  logic [31:0] conv1_drain_mxu_valid_cycles_o;
  logic [31:0] conv1_drain_psum_packer_busy_cycles_o;
  logic [31:0] conv1_drain_accum_write_cycles_o;
  logic [31:0] conv1_drain_extra_wait_cycles_o;
  logic [31:0] conv1_drain_entries_o;
  logic [31:0] conv1_accumulator_cycles_o;
  logic [31:0] conv1_vpu_cycles_o;
  logic [31:0] conv1_output_write_cycles_o;
  logic [31:0] conv1_controller_idle_cycles_o;
  logic [31:0] conv1_valid_mac_count_o;
  logic [31:0] conv1_issued_mac_count_o;
  logic [31:0] conv1_useful_mac_count_o;
  logic [31:0] conv1_exclusive_state_cycles_o;
  logic [31:0] conv2_weight_load_cycles_o;
  logic [31:0] conv2_activation_fetch_cycles_o;
  logic [31:0] conv2_mxu_active_cycles_o;
  logic [31:0] conv2_mxu_drain_cycles_o;
  logic [31:0] conv2_drain_mxu_valid_cycles_o;
  logic [31:0] conv2_drain_psum_packer_busy_cycles_o;
  logic [31:0] conv2_drain_accum_write_cycles_o;
  logic [31:0] conv2_drain_extra_wait_cycles_o;
  logic [31:0] conv2_drain_entries_o;
  logic [31:0] conv2_accumulator_cycles_o;
  logic [31:0] conv2_vpu_cycles_o;
  logic [31:0] conv2_output_write_cycles_o;
  logic [31:0] conv2_controller_idle_cycles_o;
  logic [31:0] conv2_valid_mac_count_o;
  logic [31:0] conv2_issued_mac_count_o;
  logic [31:0] conv2_useful_mac_count_o;
  logic [31:0] conv2_exclusive_state_cycles_o;
  logic [31:0] fc1_weight_load_cycles_o;
  logic [31:0] fc1_activation_fetch_cycles_o;
  logic [31:0] fc1_mxu_active_cycles_o;
  logic [31:0] fc1_mxu_drain_cycles_o;
  logic [31:0] fc1_drain_mxu_valid_cycles_o;
  logic [31:0] fc1_drain_psum_packer_busy_cycles_o;
  logic [31:0] fc1_drain_accum_write_cycles_o;
  logic [31:0] fc1_drain_extra_wait_cycles_o;
  logic [31:0] fc1_drain_entries_o;
  logic [31:0] fc1_accumulator_cycles_o;
  logic [31:0] fc1_vpu_cycles_o;
  logic [31:0] fc1_output_write_cycles_o;
  logic [31:0] fc1_controller_idle_cycles_o;
  logic [31:0] fc1_valid_mac_count_o;
  logic [31:0] fc1_issued_mac_count_o;
  logic [31:0] fc1_useful_mac_count_o;
  logic [31:0] fc1_exclusive_state_cycles_o;
  logic [(32*KLOOP_STATE_COUNT)-1:0] conv1_kloop_state_exec_counts_flat_o;
  logic [(32*KLOOP_STATE_COUNT)-1:0] conv2_kloop_state_exec_counts_flat_o;
  logic [(32*KLOOP_STATE_COUNT)-1:0] fc1_kloop_state_exec_counts_flat_o;
  logic [(32*KLOOP_STATE_COUNT)-1:0] fc2_kloop_state_exec_counts_flat_o;
  logic [(32*PREFETCH_COUNTER_COUNT)-1:0] conv1_prefetch_counts_flat_o;
  logic [(32*PREFETCH_COUNTER_COUNT)-1:0] conv2_prefetch_counts_flat_o;
  logic [(32*PREFETCH_COUNTER_COUNT)-1:0] fc1_prefetch_counts_flat_o;
  logic [(32*PREFETCH_COUNTER_COUNT)-1:0] fc2_prefetch_counts_flat_o;
  logic [31:0] fc2_mxu_drain_cycles_o;
  logic [31:0] fc2_drain_mxu_valid_cycles_o;
  logic [31:0] fc2_drain_psum_packer_busy_cycles_o;
  logic [31:0] fc2_drain_accum_write_cycles_o;
  logic [31:0] fc2_drain_extra_wait_cycles_o;
  logic [31:0] fc2_drain_entries_o;
  logic [31:0] packer_lane_fifo_nonempty_cycles_o;
  logic [31:0] packer_row_active_cycles_o;
  logic [31:0] packer_complete_row_wait_cycles_o;
  logic [31:0] packer_packed_valid_cycles_o;
  logic [31:0] packer_busy_cycles_o;
  logic [31:0] packer_lane_fifo_full_cycles_o;
  logic [31:0] packer_lane_fifo_empty_cycles_o;
  logic [31:0] packer_complete_row_backlog_cycles_o;
  logic [(32*SIZE)-1:0] packer_lane_psum_valid_cycles_flat_o;
  logic [(32*SIZE)-1:0] packer_lane_pop_cycles_flat_o;
  logic [(32*SIZE)-1:0] packer_lane_last_arrival_count_flat_o;
  logic [31:0] packer_row_completion_latency_sum_o;
  logic [31:0] packer_row_completion_latency_max_o;
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
  bit print_expected_logits_cfg;
  bit print_result_logits_cfg;
  bit print_stage_transitions_cfg;
  bit print_state_snapshots_cfg;
  bit print_phase_mac_counters_cfg;
  bit print_drain_counters_cfg;
  bit print_packer_counters_cfg;
  bit print_kloop_state_counters_cfg;
  bit print_prefetch_counters_cfg;

  top #(
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
      .DBG_STATE_COUNT    (KLOOP_STATE_COUNT),
      .DBG_PREFETCH_COUNT (PREFETCH_COUNTER_COUNT),
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
      .dbg_conv1_cycle_count_o(conv1_cycle_count_o),
      .dbg_pool1_cycle_count_o(pool1_cycle_count_o),
      .dbg_conv2_cycle_count_o(conv2_cycle_count_o),
      .dbg_pool2_cycle_count_o(pool2_cycle_count_o),
      .dbg_fc1_cycle_count_o  (fc1_cycle_count_o),
      .dbg_fc2_cycle_count_o  (fc2_cycle_count_o),
      .dbg_conv1_weight_load_cycles_o     (conv1_weight_load_cycles_o),
      .dbg_conv1_activation_fetch_cycles_o(conv1_activation_fetch_cycles_o),
      .dbg_conv1_mxu_active_cycles_o      (conv1_mxu_active_cycles_o),
      .dbg_conv1_mxu_drain_cycles_o       (conv1_mxu_drain_cycles_o),
      .dbg_conv1_drain_mxu_valid_cycles_o (conv1_drain_mxu_valid_cycles_o),
      .dbg_conv1_drain_psum_packer_busy_cycles_o(conv1_drain_psum_packer_busy_cycles_o),
      .dbg_conv1_drain_accum_write_cycles_o(conv1_drain_accum_write_cycles_o),
      .dbg_conv1_drain_extra_wait_cycles_o(conv1_drain_extra_wait_cycles_o),
      .dbg_conv1_drain_entries_o          (conv1_drain_entries_o),
      .dbg_conv1_accumulator_cycles_o     (conv1_accumulator_cycles_o),
      .dbg_conv1_vpu_cycles_o             (conv1_vpu_cycles_o),
      .dbg_conv1_output_write_cycles_o    (conv1_output_write_cycles_o),
      .dbg_conv1_controller_idle_cycles_o (conv1_controller_idle_cycles_o),
      .dbg_conv1_valid_mac_count_o        (conv1_valid_mac_count_o),
      .dbg_conv1_issued_mac_count_o       (conv1_issued_mac_count_o),
      .dbg_conv1_useful_mac_count_o       (conv1_useful_mac_count_o),
      .dbg_conv1_exclusive_state_cycles_o (conv1_exclusive_state_cycles_o),
      .dbg_conv2_weight_load_cycles_o     (conv2_weight_load_cycles_o),
      .dbg_conv2_activation_fetch_cycles_o(conv2_activation_fetch_cycles_o),
      .dbg_conv2_mxu_active_cycles_o      (conv2_mxu_active_cycles_o),
      .dbg_conv2_mxu_drain_cycles_o       (conv2_mxu_drain_cycles_o),
      .dbg_conv2_drain_mxu_valid_cycles_o (conv2_drain_mxu_valid_cycles_o),
      .dbg_conv2_drain_psum_packer_busy_cycles_o(conv2_drain_psum_packer_busy_cycles_o),
      .dbg_conv2_drain_accum_write_cycles_o(conv2_drain_accum_write_cycles_o),
      .dbg_conv2_drain_extra_wait_cycles_o(conv2_drain_extra_wait_cycles_o),
      .dbg_conv2_drain_entries_o          (conv2_drain_entries_o),
      .dbg_conv2_accumulator_cycles_o     (conv2_accumulator_cycles_o),
      .dbg_conv2_vpu_cycles_o             (conv2_vpu_cycles_o),
      .dbg_conv2_output_write_cycles_o    (conv2_output_write_cycles_o),
      .dbg_conv2_controller_idle_cycles_o (conv2_controller_idle_cycles_o),
      .dbg_conv2_valid_mac_count_o        (conv2_valid_mac_count_o),
      .dbg_conv2_issued_mac_count_o       (conv2_issued_mac_count_o),
      .dbg_conv2_useful_mac_count_o       (conv2_useful_mac_count_o),
      .dbg_conv2_exclusive_state_cycles_o (conv2_exclusive_state_cycles_o),
      .dbg_fc1_weight_load_cycles_o       (fc1_weight_load_cycles_o),
      .dbg_fc1_activation_fetch_cycles_o  (fc1_activation_fetch_cycles_o),
      .dbg_fc1_mxu_active_cycles_o        (fc1_mxu_active_cycles_o),
      .dbg_fc1_mxu_drain_cycles_o         (fc1_mxu_drain_cycles_o),
      .dbg_fc1_drain_mxu_valid_cycles_o   (fc1_drain_mxu_valid_cycles_o),
      .dbg_fc1_drain_psum_packer_busy_cycles_o(fc1_drain_psum_packer_busy_cycles_o),
      .dbg_fc1_drain_accum_write_cycles_o (fc1_drain_accum_write_cycles_o),
      .dbg_fc1_drain_extra_wait_cycles_o  (fc1_drain_extra_wait_cycles_o),
      .dbg_fc1_drain_entries_o            (fc1_drain_entries_o),
      .dbg_fc1_accumulator_cycles_o       (fc1_accumulator_cycles_o),
      .dbg_fc1_vpu_cycles_o               (fc1_vpu_cycles_o),
      .dbg_fc1_output_write_cycles_o      (fc1_output_write_cycles_o),
      .dbg_fc1_controller_idle_cycles_o   (fc1_controller_idle_cycles_o),
      .dbg_fc1_valid_mac_count_o          (fc1_valid_mac_count_o),
      .dbg_fc1_issued_mac_count_o         (fc1_issued_mac_count_o),
      .dbg_fc1_useful_mac_count_o         (fc1_useful_mac_count_o),
      .dbg_fc1_exclusive_state_cycles_o   (fc1_exclusive_state_cycles_o),
      .dbg_conv1_kloop_state_exec_counts_flat_o(conv1_kloop_state_exec_counts_flat_o),
      .dbg_conv2_kloop_state_exec_counts_flat_o(conv2_kloop_state_exec_counts_flat_o),
      .dbg_fc1_kloop_state_exec_counts_flat_o  (fc1_kloop_state_exec_counts_flat_o),
      .dbg_fc2_kloop_state_exec_counts_flat_o  (fc2_kloop_state_exec_counts_flat_o),
      .dbg_conv1_prefetch_counts_flat_o        (conv1_prefetch_counts_flat_o),
      .dbg_conv2_prefetch_counts_flat_o        (conv2_prefetch_counts_flat_o),
      .dbg_fc1_prefetch_counts_flat_o          (fc1_prefetch_counts_flat_o),
      .dbg_fc2_prefetch_counts_flat_o          (fc2_prefetch_counts_flat_o),
      .dbg_fc2_mxu_drain_cycles_o              (fc2_mxu_drain_cycles_o),
      .dbg_fc2_drain_mxu_valid_cycles_o         (fc2_drain_mxu_valid_cycles_o),
      .dbg_fc2_drain_psum_packer_busy_cycles_o  (fc2_drain_psum_packer_busy_cycles_o),
      .dbg_fc2_drain_accum_write_cycles_o       (fc2_drain_accum_write_cycles_o),
      .dbg_fc2_drain_extra_wait_cycles_o        (fc2_drain_extra_wait_cycles_o),
      .dbg_fc2_drain_entries_o                  (fc2_drain_entries_o),
      .dbg_packer_lane_fifo_nonempty_cycles_o   (packer_lane_fifo_nonempty_cycles_o),
      .dbg_packer_row_active_cycles_o           (packer_row_active_cycles_o),
      .dbg_packer_complete_row_wait_cycles_o    (packer_complete_row_wait_cycles_o),
      .dbg_packer_packed_valid_cycles_o         (packer_packed_valid_cycles_o),
      .dbg_packer_busy_cycles_o                 (packer_busy_cycles_o),
      .dbg_packer_lane_fifo_full_cycles_o       (packer_lane_fifo_full_cycles_o),
      .dbg_packer_lane_fifo_empty_cycles_o      (packer_lane_fifo_empty_cycles_o),
      .dbg_packer_complete_row_backlog_cycles_o (packer_complete_row_backlog_cycles_o),
      .dbg_packer_lane_psum_valid_cycles_flat_o (packer_lane_psum_valid_cycles_flat_o),
      .dbg_packer_lane_pop_cycles_flat_o        (packer_lane_pop_cycles_flat_o),
      .dbg_packer_lane_last_arrival_count_flat_o(packer_lane_last_arrival_count_flat_o),
      .dbg_packer_row_completion_latency_sum_o  (packer_row_completion_latency_sum_o),
      .dbg_packer_row_completion_latency_max_o  (packer_row_completion_latency_max_o),
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

  task automatic configure_print_options();
    print_expected_logits_cfg = DEFAULT_PRINT_EXPECTED_LOGITS;
    print_result_logits_cfg = DEFAULT_PRINT_RESULT_LOGITS;
    print_stage_transitions_cfg = DEFAULT_PRINT_STAGE_TRANSITIONS;
    print_state_snapshots_cfg = DEFAULT_PRINT_STATE_SNAPSHOTS;
    print_phase_mac_counters_cfg = DEFAULT_PRINT_PHASE_MAC_COUNTERS;
    print_drain_counters_cfg = DEFAULT_PRINT_DRAIN_COUNTERS;
    print_packer_counters_cfg = DEFAULT_PRINT_PACKER_COUNTERS;
    print_kloop_state_counters_cfg = DEFAULT_PRINT_KLOOP_STATE_COUNTERS;
    print_prefetch_counters_cfg = DEFAULT_PRINT_PREFETCH_COUNTERS;

    if ($test$plusargs("E2E_VERBOSE")) begin
      print_expected_logits_cfg = 1'b1;
      print_result_logits_cfg = 1'b1;
      print_stage_transitions_cfg = 1'b1;
      print_state_snapshots_cfg = 1'b1;
    end

    if ($test$plusargs("E2E_DIAG")) begin
      print_expected_logits_cfg = 1'b1;
      print_phase_mac_counters_cfg = 1'b1;
      print_drain_counters_cfg = 1'b1;
      print_packer_counters_cfg = 1'b1;
      print_kloop_state_counters_cfg = 1'b1;
      print_prefetch_counters_cfg = 1'b1;
      print_state_snapshots_cfg = 1'b1;
    end

    if ($test$plusargs("E2E_PRINT_EXPECTED")) begin
      print_expected_logits_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_LOGITS")) begin
      print_result_logits_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_STAGE")) begin
      print_stage_transitions_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_STATE")) begin
      print_state_snapshots_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_DRAIN")) begin
      print_drain_counters_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_PACKER")) begin
      print_packer_counters_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_KLOOP")) begin
      print_kloop_state_counters_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_PREFETCH")) begin
      print_prefetch_counters_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_PRINT_PHASE")) begin
      print_phase_mac_counters_cfg = 1'b1;
    end
    if ($test$plusargs("E2E_NO_LOGITS")) begin
      print_result_logits_cfg = 1'b0;
    end
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

  task automatic print_phase_counters(
      input string layer_name,
      input logic [31:0] weight_load_cycles,
      input logic [31:0] activation_fetch_cycles,
      input logic [31:0] mxu_active_cycles,
      input logic [31:0] mxu_drain_cycles,
      input logic [31:0] accumulator_cycles,
      input logic [31:0] vpu_cycles,
      input logic [31:0] output_write_cycles,
      input logic [31:0] controller_idle_cycles,
      input logic [31:0] valid_mac_count,
      input logic [31:0] issued_mac_count,
      input logic [31:0] useful_mac_count,
      input logic [31:0] exclusive_state_cycles
  );
    real mxu_active_ratio;
    real useful_pe_util;
    real useful_issued_ratio;

    mxu_active_ratio = 0.0;
    useful_pe_util = 0.0;
    useful_issued_ratio = 0.0;

    if (exclusive_state_cycles != 0) begin
      mxu_active_ratio = (100.0 * real'(mxu_active_cycles)) / real'(exclusive_state_cycles);
    end

    if (mxu_active_cycles != 0) begin
      useful_pe_util = (100.0 * real'(useful_mac_count)) /
                       real'(mxu_active_cycles * (SIZE * SIZE));
    end

    if (issued_mac_count != 0) begin
      useful_issued_ratio = (100.0 * real'(useful_mac_count)) / real'(issued_mac_count);
    end

    $display("  PHASE  %s: wgt=%0d act_fetch=%0d mxu_active=%0d drain=%0d acc=%0d vpu=%0d out=%0d idle=%0d state_sum=%0d",
             layer_name, weight_load_cycles, activation_fetch_cycles,
             mxu_active_cycles, mxu_drain_cycles, accumulator_cycles,
             vpu_cycles, output_write_cycles, controller_idle_cycles,
             exclusive_state_cycles);
    $display("  MAC    %s: valid=%0d issued=%0d useful=%0d mxu_active_ratio=%0.2f%% useful_pe_util=%0.2f%% useful_per_issued=%0.2f%%",
             layer_name, valid_mac_count, issued_mac_count, useful_mac_count,
             mxu_active_ratio, useful_pe_util, useful_issued_ratio);
  endtask

  task automatic print_drain_counters(
      input string layer_name,
      input logic [31:0] drain_total_cycles,
      input logic [31:0] drain_mxu_valid_cycles,
      input logic [31:0] drain_psum_packer_busy_cycles,
      input logic [31:0] drain_accum_write_cycles,
      input logic [31:0] drain_extra_wait_cycles,
      input logic [31:0] drain_entries
  );
    real extra_ratio;
    real drain_cycles_per_entry;

    extra_ratio = 0.0;
    drain_cycles_per_entry = 0.0;
    if (drain_total_cycles != 0) begin
      extra_ratio = (100.0 * real'(drain_extra_wait_cycles)) / real'(drain_total_cycles);
    end
    if (drain_entries != 0) begin
      drain_cycles_per_entry = real'(drain_total_cycles) / real'(drain_entries);
    end

    $display("  DRAIN  %s: total=%0d entries=%0d cyc/entry=%0.2f mxu_valid=%0d psum_busy=%0d acc_write=%0d extra_wait=%0d extra_ratio=%0.2f%%",
             layer_name, drain_total_cycles, drain_entries, drain_cycles_per_entry,
             drain_mxu_valid_cycles, drain_psum_packer_busy_cycles,
             drain_accum_write_cycles, drain_extra_wait_cycles, extra_ratio);
  endtask

  task automatic print_lane_counter_vector(
      input string label,
      input logic [(32*SIZE)-1:0] counts
  );
    $write("  PACKER %-14s {", label);
    for (int lane = 0; lane < SIZE; lane++) begin
      if (lane != 0) begin
        $write(",");
      end
      $write("%0d", counts[(lane*32)+:32]);
    end
    $display("}");
  endtask

  task automatic print_packer_counters();
    real avg_latency;
    real row_latency_per_entry;
    logic [31:0] total_drain_entries;

    avg_latency = 0.0;
    row_latency_per_entry = 0.0;
    total_drain_entries = conv1_drain_entries_o + conv2_drain_entries_o
                        + fc1_drain_entries_o + fc2_drain_entries_o;
    if (packer_packed_valid_cycles_o != 0) begin
      avg_latency = real'(packer_row_completion_latency_sum_o)
                    / real'(packer_packed_valid_cycles_o);
    end
    if (total_drain_entries != 0) begin
      row_latency_per_entry = real'(packer_row_completion_latency_sum_o)
                              / real'(total_drain_entries);
    end

    $display(
        "  PACKER : lane_nonempty=%0d row_active=%0d partial_wait=%0d packed_valid=%0d busy=%0d fifo_full=%0d fifo_empty_wait=%0d complete_backlog=%0d",
        packer_lane_fifo_nonempty_cycles_o,
        packer_row_active_cycles_o,
        packer_complete_row_wait_cycles_o,
        packer_packed_valid_cycles_o,
        packer_busy_cycles_o,
        packer_lane_fifo_full_cycles_o,
        packer_lane_fifo_empty_cycles_o,
        packer_complete_row_backlog_cycles_o);
    print_lane_counter_vector("psum_valid", packer_lane_psum_valid_cycles_flat_o);
    print_lane_counter_vector("pop", packer_lane_pop_cycles_flat_o);
    print_lane_counter_vector("last_arrival", packer_lane_last_arrival_count_flat_o);
    $display("  PACKER row_latency: sum=%0d max=%0d avg=%0.2f per_drain_entry=%0.2f total_drain_entries=%0d",
             packer_row_completion_latency_sum_o,
             packer_row_completion_latency_max_o,
             avg_latency,
             row_latency_per_entry,
             total_drain_entries);
  endtask

  function automatic logic [31:0] kloop_state_count(
      input logic [(32*KLOOP_STATE_COUNT)-1:0] counts,
      input int state_idx
  );
    kloop_state_count = counts[(state_idx*32)+:32];
  endfunction

  function automatic logic [31:0] prefetch_count(
      input logic [(32*PREFETCH_COUNTER_COUNT)-1:0] counts,
      input int counter_idx
  );
    prefetch_count = counts[(counter_idx*32)+:32];
  endfunction

  task automatic print_prefetch_counters(
      input string layer_name,
      input logic [(32*PREFETCH_COUNTER_COUNT)-1:0] counts
  );
    logic [31:0] attempts;
    logic [31:0] pushes;
    logic [31:0] hits;
    logic [31:0] misses;
    logic [31:0] drops_full;
    logic [31:0] invalidated_boundary;
    logic [31:0] queue_full_cycles;
    logic [31:0] queue_empty_on_need;
    logic [31:0] max_occupancy;
    logic [31:0] occupancy_sum;
    logic [31:0] occupancy_samples;
    logic [31:0] current_occupancy;
    logic [31:0] early_attempts;
    logic [31:0] early_pushes;
    logic [31:0] drain_attempts;
    logic [31:0] drain_pushes;
    logic [31:0] stall_queue_full;
    logic [31:0] stall_ub_busy;
    logic [31:0] stall_no_candidate;
    logic [31:0] miss_no_entry;
    logic [31:0] miss_tag_mismatch;
    logic [31:0] miss_lane_incomplete;
    logic [31:0] miss_invalid_boundary;
    logic [31:0] miss_wrong_k_tile;
    logic [31:0] miss_wrong_spatial;
    logic [31:0] miss_wrong_oc_tile;
    logic [31:0] vector_start_count;
    logic [31:0] vector_push_count;
    logic [31:0] lane_req_count;
    logic [31:0] lane_capture_count;
    logic [31:0] issue_cycles;
    logic [31:0] bubble_cycles;
    logic [31:0] busy_cycles;
    logic [31:0] demand_count;
    real hit_rate;
    real avg_occupancy;
    real cycles_per_vector;
    real issue_efficiency;

    attempts = prefetch_count(counts, PREFETCH_ATTEMPTS);
    pushes = prefetch_count(counts, PREFETCH_PUSHES);
    hits = prefetch_count(counts, PREFETCH_HITS);
    misses = prefetch_count(counts, PREFETCH_MISSES);
    drops_full = prefetch_count(counts, PREFETCH_DROPS_FULL);
    invalidated_boundary = prefetch_count(counts, PREFETCH_INVALIDATED_BOUNDARY);
    queue_full_cycles = prefetch_count(counts, PREFETCH_QUEUE_FULL_CYCLES);
    queue_empty_on_need = prefetch_count(counts, PREFETCH_QUEUE_EMPTY_ON_NEED);
    max_occupancy = prefetch_count(counts, PREFETCH_MAX_OCCUPANCY);
    occupancy_sum = prefetch_count(counts, PREFETCH_OCCUPANCY_SUM);
    occupancy_samples = prefetch_count(counts, PREFETCH_OCCUPANCY_SAMPLES);
    current_occupancy = prefetch_count(counts, PREFETCH_CURRENT_OCCUPANCY);
    early_attempts = prefetch_count(counts, PREFETCH_EARLY_ATTEMPTS);
    early_pushes = prefetch_count(counts, PREFETCH_EARLY_PUSHES);
    drain_attempts = prefetch_count(counts, PREFETCH_DRAIN_ATTEMPTS);
    drain_pushes = prefetch_count(counts, PREFETCH_DRAIN_PUSHES);
    stall_queue_full = prefetch_count(counts, PREFETCH_STALL_QUEUE_FULL);
    stall_ub_busy = prefetch_count(counts, PREFETCH_STALL_UB_BUSY);
    stall_no_candidate = prefetch_count(counts, PREFETCH_STALL_NO_CANDIDATE);
    miss_no_entry = prefetch_count(counts, PREFETCH_MISS_NO_ENTRY);
    miss_tag_mismatch = prefetch_count(counts, PREFETCH_MISS_TAG_MISMATCH);
    miss_lane_incomplete = prefetch_count(counts, PREFETCH_MISS_LANE_INCOMPLETE);
    miss_invalid_boundary = prefetch_count(counts, PREFETCH_MISS_INVALID_BOUNDARY);
    miss_wrong_k_tile = prefetch_count(counts, PREFETCH_MISS_WRONG_K_TILE);
    miss_wrong_spatial = prefetch_count(counts, PREFETCH_MISS_WRONG_SPATIAL);
    miss_wrong_oc_tile = prefetch_count(counts, PREFETCH_MISS_WRONG_OC_TILE);
    vector_start_count = prefetch_count(counts, PREFETCH_VECTOR_START);
    vector_push_count = prefetch_count(counts, PREFETCH_VECTOR_PUSH);
    lane_req_count = prefetch_count(counts, PREFETCH_LANE_REQ);
    lane_capture_count = prefetch_count(counts, PREFETCH_LANE_CAPTURE);
    issue_cycles = prefetch_count(counts, PREFETCH_ISSUE_CYCLES);
    bubble_cycles = prefetch_count(counts, PREFETCH_BUBBLE_CYCLES);
    busy_cycles = prefetch_count(counts, PREFETCH_BUSY_CYCLES);
    demand_count = hits + misses;
    hit_rate = 0.0;
    avg_occupancy = 0.0;
    cycles_per_vector = 0.0;
    issue_efficiency = 0.0;

    if (demand_count != 0) begin
      hit_rate = (100.0 * real'(hits)) / real'(demand_count);
    end
    if (occupancy_samples != 0) begin
      avg_occupancy = real'(occupancy_sum) / real'(occupancy_samples);
    end
    if (vector_push_count != 0) begin
      cycles_per_vector = real'(busy_cycles) / real'(vector_push_count);
    end
    if (busy_cycles != 0) begin
      issue_efficiency = (100.0 * real'(issue_cycles)) / real'(busy_cycles);
    end

    $display("  PREFETCH %s: attempts=%0d pushes=%0d hits=%0d misses=%0d hit_rate=%0.2f%%",
             layer_name, attempts, pushes, hits, misses, hit_rate);
    $display("  PREFETCH %s: drops_full=%0d invalid_boundary=%0d full_cycles=%0d empty_on_need=%0d max_occ=%0d avg_occ=%0.2f curr_occ=%0d",
             layer_name, drops_full, invalidated_boundary, queue_full_cycles,
             queue_empty_on_need, max_occupancy, avg_occupancy, current_occupancy);
    $display("  PREFETCH %s: early_attempts=%0d early_pushes=%0d drain_attempts=%0d drain_pushes=%0d",
             layer_name, early_attempts, early_pushes, drain_attempts, drain_pushes);
    $display("  PREFETCH %s: stall_queue_full=%0d stall_ub_busy=%0d stall_no_candidate=%0d",
             layer_name, stall_queue_full, stall_ub_busy, stall_no_candidate);
    $display("  PREFETCH %s miss_breakdown: no_entry=%0d tag_mismatch=%0d lane_incomplete=%0d invalid_boundary=%0d wrong_k=%0d wrong_spatial=%0d wrong_oc=%0d",
             layer_name, miss_no_entry, miss_tag_mismatch, miss_lane_incomplete,
             miss_invalid_boundary, miss_wrong_k_tile, miss_wrong_spatial,
             miss_wrong_oc_tile);
    $display("  PREFETCH %s micro: vec_start=%0d vec_push=%0d lane_req=%0d lane_cap=%0d issue=%0d bubble=%0d busy=%0d cyc_per_vec=%0.2f issue_eff=%0.2f%%",
             layer_name, vector_start_count, vector_push_count, lane_req_count,
             lane_capture_count, issue_cycles, bubble_cycles, busy_cycles,
             cycles_per_vector, issue_efficiency);
  endtask

  task automatic print_kloop_state_counters(
      input string layer_name,
      input logic [(32*KLOOP_STATE_COUNT)-1:0] counts
  );
    logic [31:0] state_sum;

    state_sum = '0;
    for (int state_idx = 0; state_idx < KLOOP_STATE_COUNT; state_idx++) begin
      state_sum = state_sum + kloop_state_count(counts, state_idx);
    end

    $display("  KLOOP  %s 1cyc-candidates: clear=%0d fetch=%0d wait_rom=%0d wgt_row=%0d start_wgt=%0d act_req=%0d launch=%0d acc_read=%0d out_lane=%0d",
             layer_name,
             kloop_state_count(counts, KLOOP_S_CLEAR_ACC_BLOCK),
             kloop_state_count(counts, KLOOP_S_FETCH_ROM),
             kloop_state_count(counts, KLOOP_S_WAIT_ROM),
             kloop_state_count(counts, KLOOP_S_WRITE_WEIGHT_ROW),
             kloop_state_count(counts, KLOOP_S_START_WEIGHT_LOAD),
             kloop_state_count(counts, KLOOP_S_READ_ACT_REQ),
             kloop_state_count(counts, KLOOP_S_LAUNCH_ACT),
             kloop_state_count(counts, KLOOP_S_READ_ACC_ROW),
             kloop_state_count(counts, KLOOP_S_WRITE_OUTPUT_LANE));
    $display("  KLOOP  %s waits/drain: wgt_wait=%0d act_wait=%0d drain=%0d acc_wait=%0d vpu_wait=%0d state_sum=%0d",
             layer_name,
             kloop_state_count(counts, KLOOP_S_WAIT_WEIGHT_LOAD),
             kloop_state_count(counts, KLOOP_S_READ_ACT_WAIT),
             kloop_state_count(counts, KLOOP_S_DRAIN_MXU),
             kloop_state_count(counts, KLOOP_S_WAIT_ACC_READY),
             kloop_state_count(counts, KLOOP_S_WAIT_VPU_OUTPUT),
             state_sum);
  endtask

  task automatic print_cycle_counters(input int observed_cycles);
    logic [31:0] layer_sum;

    layer_sum = conv1_cycle_count_o + pool1_cycle_count_o + conv2_cycle_count_o
              + pool2_cycle_count_o + fc1_cycle_count_o + fc2_cycle_count_o;

    $display("  CYCLES : observed=%0d rtl_total=%0d layer_sum=%0d",
             observed_cycles, cycle_count_o, layer_sum);
    $display("  LAYERS : conv1=%0d pool1=%0d conv2=%0d pool2=%0d fc1=%0d fc2=%0d",
             conv1_cycle_count_o, pool1_cycle_count_o, conv2_cycle_count_o,
             pool2_cycle_count_o, fc1_cycle_count_o, fc2_cycle_count_o);
    if (print_phase_mac_counters_cfg) begin
      print_phase_counters("conv1",
                           conv1_weight_load_cycles_o,
                           conv1_activation_fetch_cycles_o,
                           conv1_mxu_active_cycles_o,
                           conv1_mxu_drain_cycles_o,
                           conv1_accumulator_cycles_o,
                           conv1_vpu_cycles_o,
                           conv1_output_write_cycles_o,
                           conv1_controller_idle_cycles_o,
                           conv1_valid_mac_count_o,
                           conv1_issued_mac_count_o,
                           conv1_useful_mac_count_o,
                           conv1_exclusive_state_cycles_o);
      print_phase_counters("conv2",
                           conv2_weight_load_cycles_o,
                           conv2_activation_fetch_cycles_o,
                           conv2_mxu_active_cycles_o,
                           conv2_mxu_drain_cycles_o,
                           conv2_accumulator_cycles_o,
                           conv2_vpu_cycles_o,
                           conv2_output_write_cycles_o,
                           conv2_controller_idle_cycles_o,
                           conv2_valid_mac_count_o,
                           conv2_issued_mac_count_o,
                           conv2_useful_mac_count_o,
                           conv2_exclusive_state_cycles_o);
      print_phase_counters("fc1",
                           fc1_weight_load_cycles_o,
                           fc1_activation_fetch_cycles_o,
                           fc1_mxu_active_cycles_o,
                           fc1_mxu_drain_cycles_o,
                           fc1_accumulator_cycles_o,
                           fc1_vpu_cycles_o,
                           fc1_output_write_cycles_o,
                           fc1_controller_idle_cycles_o,
                           fc1_valid_mac_count_o,
                           fc1_issued_mac_count_o,
                           fc1_useful_mac_count_o,
                           fc1_exclusive_state_cycles_o);
    end

    if (print_drain_counters_cfg) begin
      print_drain_counters("conv1",
                           conv1_mxu_drain_cycles_o,
                           conv1_drain_mxu_valid_cycles_o,
                           conv1_drain_psum_packer_busy_cycles_o,
                           conv1_drain_accum_write_cycles_o,
                           conv1_drain_extra_wait_cycles_o,
                           conv1_drain_entries_o);
      print_drain_counters("conv2",
                           conv2_mxu_drain_cycles_o,
                           conv2_drain_mxu_valid_cycles_o,
                           conv2_drain_psum_packer_busy_cycles_o,
                           conv2_drain_accum_write_cycles_o,
                           conv2_drain_extra_wait_cycles_o,
                           conv2_drain_entries_o);
      print_drain_counters("fc1",
                           fc1_mxu_drain_cycles_o,
                           fc1_drain_mxu_valid_cycles_o,
                           fc1_drain_psum_packer_busy_cycles_o,
                           fc1_drain_accum_write_cycles_o,
                           fc1_drain_extra_wait_cycles_o,
                           fc1_drain_entries_o);
      print_drain_counters("fc2",
                           fc2_mxu_drain_cycles_o,
                           fc2_drain_mxu_valid_cycles_o,
                           fc2_drain_psum_packer_busy_cycles_o,
                           fc2_drain_accum_write_cycles_o,
                           fc2_drain_extra_wait_cycles_o,
                           fc2_drain_entries_o);
    end

    if (print_packer_counters_cfg) begin
      print_packer_counters();
    end

    if (print_kloop_state_counters_cfg) begin
      print_kloop_state_counters("conv1", conv1_kloop_state_exec_counts_flat_o);
      print_kloop_state_counters("conv2", conv2_kloop_state_exec_counts_flat_o);
      print_kloop_state_counters("fc1", fc1_kloop_state_exec_counts_flat_o);
      print_kloop_state_counters("fc2", fc2_kloop_state_exec_counts_flat_o);
    end

    if (print_prefetch_counters_cfg) begin
      print_prefetch_counters("conv1", conv1_prefetch_counts_flat_o);
      print_prefetch_counters("conv2", conv2_prefetch_counts_flat_o);
      print_prefetch_counters("fc1", fc1_prefetch_counts_flat_o);
      print_prefetch_counters("fc2", fc2_prefetch_counts_flat_o);
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
    configure_case(case_idx);
    print_header($sformatf("CASE %0d: %s", case_idx, current_case_name));

    for (int idx = 0; idx < INPUT_COUNT; idx++) begin
      host_write(1'b0, UB_ADDR_WIDTH'(idx), input_mem[idx]);
    end

    $display("  preload: ub_bank0[0:%0d] schedule=Conv1->Pool1->Conv2->Pool2->FC1->FC2",
             INPUT_COUNT - 1);
    if (print_expected_logits_cfg) begin
      print_expected_logits();
    end
  endtask

  task automatic run_top(input int case_idx);
    int cycles;
    logic [2:0] last_stage;

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

      if (print_stage_transitions_cfg && (stage_o != last_stage)) begin
        $display("  stage=%0d cycle=%0d layer_state=%0d pool_state=%0d",
                 stage_o, cycles, layer_state_o, pool_state_o);
        last_stage = stage_o;
      end
    end

    $display("  TOP    : done=%b busy=%b error=%b state=%0d stage=%0d cycles=%0d err=0x%08h",
             done_o, busy_o, error_o, state_o, stage_o, cycles, error_code_o);
    print_cycle_counters(cycles);
    if (print_state_snapshots_cfg) begin
      $display("  LAYER  : state=%0d tile_state=%0d spatial=%0d oc_tile=%0d k_tile=%0d",
               layer_state_o, layer_tile_state_o, layer_spatial_o,
               layer_oc_tile_o, layer_k_tile_o);
      $display("  POOL   : state=%0d channel=%0d row=%0d col=%0d",
               pool_state_o, pool_channel_o, pool_row_o, pool_col_o);
    end

    expect_flag("top finished", done_o);
    expect_flag("top no error", !error_o);
    expect_flag("datapath no overflow", overflow_flatten == '0);
  endtask

  task automatic check_logits(input int case_idx);
    logic signed [DATA_WIDTH-1:0] actual;
    logic signed [DATA_WIDTH-1:0] actual_logits[0:LOGIT_COUNT-1];
    int mismatch_count;

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

    if (print_result_logits_cfg || (mismatch_count != 0) || (runtime_case_count <= LOGIT_PRINT_CASE_LIMIT)) begin
      $display("  actual logits   {%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d}",
               $signed(actual_logits[0]), $signed(actual_logits[1]),
               $signed(actual_logits[2]), $signed(actual_logits[3]),
               $signed(actual_logits[4]), $signed(actual_logits[5]),
               $signed(actual_logits[6]), $signed(actual_logits[7]),
               $signed(actual_logits[8]), $signed(actual_logits[9]));
      print_expected_logits();
    end
    $display("  mismatches: %0d", mismatch_count);
  endtask

  initial begin
    init_signals();
    configure_print_options();
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
