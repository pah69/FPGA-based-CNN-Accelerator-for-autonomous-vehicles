`timescale 1ns / 1ps

module mxu_2x2 #(
    parameter int SIZE             = 2,
    parameter int DATA_WIDTH       = 8,
    parameter int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int NUM_TILES        = SIZE,
    parameter int ACC_WIDTH        = 32,
    parameter bit ENABLE_LOCAL_ACCUM = 1'b1,
    parameter int WGT_FIFO_DEPTH   = 16, // Độ sâu của FIFO Trọng số
    parameter int WGT_FIFO_COUNT_WIDTH = (WGT_FIFO_DEPTH > 0) ? $clog2(WGT_FIFO_DEPTH + 1) : 1,
    parameter int TILE_COUNT_WIDTH = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1,
    parameter int MAC_COUNT_WIDTH  = (SIZE*SIZE > 1) ? $clog2((SIZE*SIZE) + 1) : 1
) (
    input logic clk,
    input logic rst_n,
    input logic work_i,
    // Runtime K-tile count passed through to optional local accumulators.
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    // ========================================
    // Điều khiển nạp trọng số tự động
    // ========================================
    input  logic start_wgt_load_i, // Xung kích hoạt bơm trọng số từ FIFO vào mảng
    output logic wgt_fetcher_ready_o,

    // ========================================
    // Giao tiếp Ghi vào Weight FIFO (Từ Host/AXI)
    // ========================================
    input  logic [(DATA_WIDTH*SIZE)-1:0] wgt_fifo_wdata_i,
    input  logic                         wgt_fifo_wr_en_i,
    output logic                         wgt_fifo_full_o,
    output logic                         wgt_fifo_empty_o,

    // ========================================
    // Giao tiếp Dữ liệu Ảnh (Từ Unified Buffer)
    // ========================================
    input logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_i,
    input logic        [SIZE-1:0]              act_valid_raw_i,

    // ========================================
    // Giao tiếp Đầu ra Partial Sum (Tới Accumulator)
    // ========================================
    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o,
    output logic        [SIZE-1:0]                    psum_valid_o,
    output logic        [MAC_COUNT_WIDTH-1:0]          valid_mac_count_o,
    output logic signed [(ACC_WIDTH*SIZE)-1:0]       result_flatten_o,
    output logic                                      done_o,

    // ========================================
    // Tín hiệu Trạng thái
    // ========================================
    output logic [SIZE-1:0]      wgt_load_done_o,
    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o
);

    // ========================================================
    // Dây nối nội bộ
    // ========================================================
    // Giữa Skew Buffer và SA
    logic signed [(DATA_WIDTH*SIZE)-1:0] act_skewed_w;
    logic        [SIZE-1:0]              act_valid_skewed_w;

    // Giữa FIFO và Fetcher
    logic [(DATA_WIDTH*SIZE)-1:0] internal_fifo_rdata;
    logic                         internal_fifo_empty;
    logic                         internal_fifo_rd_en;
    logic [WGT_FIFO_COUNT_WIDTH-1:0] internal_fifo_count;

    // Giữa Fetcher và SA
    logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_w;
    logic        [SIZE-1:0]              wgt_load_w;
    logic                                weight_switch_w;

    // ========================================================
    // 1. Tích hợp thiết kế FIFO của bạn!
    // ========================================================
    fifo #(
        .WIDTH      (DATA_WIDTH * SIZE),
        .DEPTH      (WGT_FIFO_DEPTH),
        .COUNT_WIDTH(WGT_FIFO_COUNT_WIDTH)
    ) u_weight_fifo (
        .clk_i   (clk),
        .rst_n_i (rst_n),
        
        .wdata_i (wgt_fifo_wdata_i),
        .wr_en_i (wgt_fifo_wr_en_i),
        .full_o  (wgt_fifo_full_o),
        
        .rdata_o (internal_fifo_rdata),
        .rd_en_i (internal_fifo_rd_en),
        .empty_o (internal_fifo_empty),
        .count_o (internal_fifo_count)
    );

    assign wgt_fifo_empty_o = internal_fifo_empty;

    // ========================================================
    // 2. Tích hợp Khối tự động lấy Trọng số (Weight Fetcher)
    // ========================================================
    wgt_fetcher_2x2 #(
        .SIZE            (SIZE),
        .DATA_WIDTH      (DATA_WIDTH),
        .FIFO_COUNT_WIDTH(WGT_FIFO_COUNT_WIDTH)
    ) u_wgt_fetcher (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_load_i    (start_wgt_load_i),
        .ready_o         (wgt_fetcher_ready_o),
        
        // Giao tiếp với khối FIFO của bạn
        .fifo_data_i     (internal_fifo_rdata),
        .fifo_empty_i    (internal_fifo_empty),
        .fifo_count_i    (internal_fifo_count),
        .fifo_pop_o      (internal_fifo_rd_en),
        
        // Giao tiếp với SA
        .wgt_flatten_o   (wgt_flatten_w),
        .wgt_load_o      (wgt_load_w),
        .weight_switch_o (weight_switch_w)
    );

    // ========================================================
    // 3. Tích hợp Skew Buffer (Ảnh)
    // ========================================================
    act_skew_buffer_2x2 #(
        .SIZE(SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew_buffer (
        .clk               (clk),
        .rst_n             (rst_n),
        .act_flat_raw_i    (act_flat_raw_i),
        .act_valid_raw_i   (act_valid_raw_i),
        .act_skewed_o      (act_skewed_w),
        .act_valid_skewed_o(act_valid_skewed_w)
    );

    // ========================================================
    // 4. Mảng Systolic Array 2x2
    // ========================================================
    ws_sa_2x2 #(
        .SIZE(SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
        .NUM_TILES(NUM_TILES),
        .ACC_WIDTH(ACC_WIDTH),
        .ENABLE_LOCAL_ACCUM(ENABLE_LOCAL_ACCUM)
    ) u_systolic_array (
        .clk               (clk),
        .rst_n             (rst_n),
        .work_i            (work_i),
        .num_tiles_i       (num_tiles_i),
        
        .act_flatten_i     (act_skewed_w),
        .act_valid_i       (act_valid_skewed_w),
        
        .wgt_flatten_i     (wgt_flatten_w),
        .wgt_load_i        (wgt_load_w),
        .weight_switch_i   (weight_switch_w),
        
        .psum_flatten_o    (psum_flatten_o),
        .psum_valid_o      (psum_valid_o),
        .valid_mac_count_o (valid_mac_count_o),
        .result_flatten_o  (result_flatten_o),
        .done_o            (done_o),
        .wgt_load_done_o   (wgt_load_done_o),
        .overflow_clr_i    (overflow_clr_i),
        .overflow_flatten_o(overflow_flatten_o)
    );

endmodule
