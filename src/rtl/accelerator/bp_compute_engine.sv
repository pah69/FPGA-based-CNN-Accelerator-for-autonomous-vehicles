

`timescale 1ns / 1ps

module bp_compute_engine #(
    parameter int DATA_WIDTH = 17,
    parameter int SIZE       = 64,
    parameter int PSUM_WIDTH = (2 * DATA_WIDTH) + 8  // 42-bit
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // 1. Giao tiếp với Input SRAM (Weight & Activation)
    // ========================================
    // Weight (Băng thông hẹp: 17-bit/clock)
    input logic [DATA_WIDTH-1:0] sram_wgt_i,
    input logic                  sram_wgt_valid_i,

    // Activation (Băng thông rộng: 1088-bit/clock)
    input logic [(DATA_WIDTH*SIZE)-1:0] sram_act_flatten_i,
    input logic [             SIZE-1:0] sram_act_valid_i,

    // ========================================
    // 2. Giao tiếp với Output SRAM & Controller
    // ========================================
    input  logic                         sram_read_en_i,  // FSM cho phép xuất data ra SRAM
    output logic [(DATA_WIDTH*SIZE)-1:0] sram_data_o,     // Data gửi ra Output SRAM
    output logic                         fifo_full_o,     // Báo cho FSM biết FIFO đầy
    output logic                         fifo_empty_o     // Báo cho FSM biết FIFO rỗng

);

  // Internal wires
  logic [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_to_sa;
  logic                         wgt_load_to_sa;

  // Giữa Act Buff và SA
  logic [(DATA_WIDTH*SIZE)-1:0] act_flatten_to_sa;
  logic [             SIZE-1:0] act_valid_to_sa;

  // Giữa SA và Post-Processing
  logic [(PSUM_WIDTH*SIZE)-1:0] psum_flatten_to_post;
  logic [             SIZE-1:0] psum_valid_to_post;

  // Giữa Post-Processing và Out Buff
  logic [(DATA_WIDTH*SIZE)-1:0] data_flatten_to_fifo;
  logic [             SIZE-1:0] data_valid_to_fifo;



  // Local activation buffer
  bp_local_act_buff #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE)
  ) u_local_act_buff (
      .clk               (clk),
      .rst_n             (rst_n),
      .sram_act_flatten_i(sram_act_flatten_i),
      .sram_act_valid_i  (sram_act_valid_i),
      .sa_act_flatten_o  (act_flatten_to_sa),
      .sa_act_valid_o    (act_valid_to_sa)
  );

  // Local weight buffer
  bp_local_weight_buff #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE)
  ) u_local_weight_buff (
      .clk             (clk),
      .rst_n           (rst_n),
      .sram_wgt_i      (sram_wgt_i),
      .sram_wgt_valid_i(sram_wgt_valid_i),
      .sa_wgt_flatten_o(wgt_flatten_to_sa),
      .sa_wgt_load_o   (wgt_load_to_sa)
  );


  // Systolic Array size NxN
  bp_sa_64x64 #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) u_sa_64x64 (
      .clk           (clk),
      .rst_n         (rst_n),
      .wgt_flatten_i (wgt_flatten_to_sa),
      .wgt_load_i    (wgt_load_to_sa),
      .act_flatten_i (act_flatten_to_sa),
      .act_valid_i   (act_valid_to_sa),
      .psum_flatten_o(psum_flatten_to_post),
      .psum_valid_o  (psum_valid_to_post)
  );

  // Post processing unit
  bp_post_proc #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE),
      .PSUM_WIDTH(PSUM_WIDTH),
      .QUANT_SHIFT(8)  // Thông số dịch bit (có thể tinh chỉnh)
  ) u_post_proc (
      .clk           (clk),
      .rst_n         (rst_n),
      .psum_flatten_i(psum_flatten_to_post),
      .psum_valid_i  (psum_valid_to_post),
      .data_flatten_o(data_flatten_to_fifo),
      .data_valid_o  (data_valid_to_fifo)
  );


  // Local output buffer
  bp_local_out_buff #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE),
      .DEPTH(16)
  ) u_local_out_buff (
      .clk           (clk),
      .rst_n         (rst_n),
      .post_data_i   (data_flatten_to_fifo),
      .post_valid_i  (data_valid_to_fifo),
      .sram_read_en_i(sram_read_en_i),
      .sram_data_o   (sram_data_o),
      .fifo_full_o   (fifo_full_o),
      .fifo_empty_o  (fifo_empty_o)
  );

endmodule
