module ws_sa_3x3 #(
    parameter int DATA_WIDTH = 17,
    parameter int PSUM_WIDTH = (2 * DATA_WIDTH) + 8
) (
    input logic clk,
    input logic rst_n,

    // weight
    input logic [(DATA_WIDTH*4)-1:0] wgt_flatten_i,
    input logic                      wgt_load_i,

    // activation in
    input logic [(DATA_WIDTH*4)-1:0] act_flatten_i,
    // input logic                      act_flatten_valid_i,
    input logic [               2:0] act_valid_i,

    // Partial sum stream (Kết quả chảy ra từ bên dưới)
    output logic [(PSUM_WIDTH*3)-1:0] psum_flatten_o,
    output logic [               2:0] psum_valid_o,    // Tín hiệu valid độc lập cho 3 cột

    // activation out
    output logic [(DATA_WIDTH*4)-1:0] act_flatten_o,
    input  logic                      act_flatten_valid_o

);

  // activation in register : activation move left to right horizontally
  logic signed [DATA_WIDTH-1:0] act_00_to_01, act_01_to_02;
  logic act_v_00_to_01, act_v_01_to_02;

  logic signed [DATA_WIDTH-1:0] act_10_to_11, act_11_to_12;
  logic act_v_10_to_11, act_v_11_to_12;

  logic signed [DATA_WIDTH-1:0] act_20_to_21, act_21_to_22;
  logic act_v_20_to_21, act_v_21_to_22;

  // weight in register : Weight move down vertically
  logic signed [DATA_WIDTH-1:0] wgt_00_to_10, wgt_10_to_20;
  logic signed [DATA_WIDTH-1:0] wgt_01_to_11, wgt_11_to_21;
  logic signed [DATA_WIDTH-1:0] wgt_02_to_12, wgt_12_to_22;

  // partial sum register : partial sum move down vertically
  logic signed [PSUM_WIDTH-1:0] psum_00_to_10, psum_10_to_20, psum_20_out;
  logic psum_v_00_to_10, psum_v_10_to_20, psum_v_20_out;

  logic signed [PSUM_WIDTH-1:0] psum_01_to_11, psum_11_to_21, psum_21_out;
  logic psum_v_01_to_11, psum_v_11_to_21, psum_v_21_out;

  logic signed [PSUM_WIDTH-1:0] psum_02_to_12, psum_12_to_22, psum_22_out;
  logic psum_v_02_to_12, psum_v_12_to_22, psum_v_22_out;


  // reg connect to input ports of the Systolic Array
  // activation in unpack into 1D vector
  logic signed [DATA_WIDTH-1:0] act_row0_i, act_row1_i, act_row2_i, act_row3_i;
  assign act_row0_i = act_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  assign act_row1_i = act_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];
  assign act_row2_i = act_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH];
  assign act_row3_i = act_flatten_i[(3*DATA_WIDTH)+:DATA_WIDTH];


  // weight  
  logic signed [DATA_WIDTH-1:0] wgt_col0_i, wgt_col1_i, wgt_col2_i, wgt_col3_i;
  assign wgt_col0_i = wgt_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  assign wgt_col1_i = wgt_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];
  assign wgt_col2_i = wgt_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH];
  assign wgt_col3_i = wgt_flatten_i[(3*DATA_WIDTH)+:DATA_WIDTH];


  // output packed into 1 long 
  // Pack dữ liệu đầu ra (Psum từ hàng cuối cùng)
  assign psum_flatten_o[(0*PSUM_WIDTH)+:PSUM_WIDTH] = psum_20_out;
  assign psum_flatten_o[(1*PSUM_WIDTH)+:PSUM_WIDTH] = psum_21_out;
  assign psum_flatten_o[(2*PSUM_WIDTH)+:PSUM_WIDTH] = psum_22_out;

  assign psum_valid_o[0] = psum_v_20_out;
  assign psum_valid_o[1] = psum_v_21_out;
  assign psum_valid_o[2] = psum_v_22_out;



  // ==========================================
  // ROW 0
  // ==========================================

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_00 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_row0_i),
      .act_valid_i  (act_valid_i[0]),
      .act_o        (act_00_to_01),
      .act_valid_o  (act_v_00_to_01),
      .psum_i       ('0),               // Psum đầu tiên luôn là 0
      .psum_valid_i (1'b1),             // Luôn valid để phép cộng diễn ra
      .psum_o       (psum_00_to_10),
      .psum_valid_o (psum_v_00_to_10),
      .weight_i     (wgt_col0_i),
      .weight_load_i(wgt_load_i),
      .weight_o     (wgt_00_to_10)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_01 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_00_to_01),
      .act_valid_i  (act_v_00_to_01),
      .act_o        (act_01_to_02),
      .act_valid_o  (act_v_01_to_02),
      .psum_i       ('0),
      .psum_valid_i (1'b1),
      .psum_o       (psum_01_to_11),
      .psum_valid_o (psum_v_01_to_11),
      .weight_i     (wgt_col1_i),
      .weight_load_i(wgt_load_i),
      .weight_o     (wgt_01_to_11)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_02 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_01_to_02),
      .act_valid_i  (act_v_01_to_02),
      .act_o        (),                 // Hàng cuối không dùng act_o
      .act_valid_o  (),
      .psum_i       ('0),
      .psum_valid_i (1'b1),
      .psum_o       (psum_02_to_12),
      .psum_valid_o (psum_v_02_to_12),
      .weight_i     (wgt_col2_i),
      .weight_load_i(wgt_load_i),
      .weight_o     (wgt_02_to_12)
  );

  // ==========================================
  // ROW 1
  // ==========================================

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_10 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_row1_i),
      .act_valid_i  (act_valid_i[1]),
      .act_o        (act_10_to_11),
      .act_valid_o  (act_v_10_to_11),
      .psum_i       (psum_00_to_10),
      .psum_valid_i (psum_v_00_to_10),
      .psum_o       (psum_10_to_20),
      .psum_valid_o (psum_v_10_to_20),
      .weight_i     (wgt_00_to_10),
      .weight_load_i(wgt_load_i),
      .weight_o     (wgt_10_to_20)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_11 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_10_to_11),
      .act_valid_i  (act_v_10_to_11),
      .act_o        (act_11_to_12),
      .act_valid_o  (act_v_11_to_12),
      .psum_i       (psum_01_to_11),
      .psum_valid_i (psum_v_01_to_11),
      .psum_o       (psum_11_to_21),
      .psum_valid_o (psum_v_11_to_21),
      .weight_i     (wgt_01_to_11),
      .weight_load_i(wgt_load_i),
      .weight_o     (wgt_11_to_21)
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_12 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_11_to_12),
      .act_valid_i  (act_v_11_to_12),
      .act_o        (),
      .act_valid_o  (),
      .psum_i       (psum_02_to_12),
      .psum_valid_i (psum_v_02_to_12),
      .psum_o       (psum_12_to_22),
      .psum_valid_o (psum_v_12_to_22),
      .weight_i     (wgt_02_to_12),
      .weight_load_i(wgt_load_i),
      .weight_o     (wgt_12_to_22)
  );

  // ==========================================
  // ROW 2
  // ==========================================

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_20 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_row2_i),
      .act_valid_i  (act_valid_i[2]),
      .act_o        (act_20_to_21),
      .act_valid_o  (act_v_20_to_21),
      .psum_i       (psum_10_to_20),
      .psum_valid_i (psum_v_10_to_20),
      .psum_o       (psum_20_out),
      .psum_valid_o (psum_v_20_out),
      .weight_i     (wgt_10_to_20),
      .weight_load_i(wgt_load_i),
      .weight_o     ()                  // Hàng cuối không cần truyền weight đi nữa
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_21 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_20_to_21),
      .act_valid_i  (act_v_20_to_21),
      .act_o        (act_21_to_22),
      .act_valid_o  (act_v_21_to_22),
      .psum_i       (psum_11_to_21),
      .psum_valid_i (psum_v_11_to_21),
      .psum_o       (psum_21_out),
      .psum_valid_o (psum_v_21_out),
      .weight_i     (wgt_11_to_21),
      .weight_load_i(wgt_load_i),
      .weight_o     ()
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) pe_22 (
      .clk          (clk),
      .rst_n        (rst_n),
      .act_i        (act_21_to_22),
      .act_valid_i  (act_v_21_to_22),
      .act_o        (),
      .act_valid_o  (),
      .psum_i       (psum_12_to_22),
      .psum_valid_i (psum_v_12_to_22),
      .psum_o       (psum_22_out),
      .psum_valid_o (psum_v_22_out),
      .weight_i     (wgt_12_to_22),
      .weight_load_i(wgt_load_i),
      .weight_o     ()
  );

endmodule
