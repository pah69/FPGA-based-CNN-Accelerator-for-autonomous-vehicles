`timescale 1ns/1ps

module tb;

parameter DATA_WIDTH = 17;
parameter ROWS = 2;
parameter COLS = 2;
parameter DEPTH = 16;
parameter ADDR_WIDTH = $clog2(DEPTH);
parameter ACC_WIDTH = (2*DATA_WIDTH)+1;
parameter OUT_WIDTH = ROWS*COLS*ACC_WIDTH;

logic clk;
logic rst_n;

logic start_i;
logic [ADDR_WIDTH:0] k_steps_i;

logic busy_o;
logic done_o;

logic act_buf_wr_en_i;
logic [ADDR_WIDTH-1:0] act_buf_wr_addr_i;
logic [ROWS*DATA_WIDTH-1:0] act_buf_wr_data_i;

logic weight_buf_wr_en_i;
logic [ADDR_WIDTH-1:0] weight_buf_wr_addr_i;
logic [COLS*DATA_WIDTH-1:0] weight_buf_wr_data_i;

logic out_buf_rd_en_i;
logic [ADDR_WIDTH-1:0] out_buf_rd_addr_i;
logic [OUT_WIDTH-1:0] out_buf_rd_data_o;

logic signed [ACC_WIDTH-1:0] C00, C01, C10, C11;

cnn_accelerator_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .ROWS(ROWS),
    .COLS(COLS),
    .DEPTH(DEPTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .k_steps_i(k_steps_i),
    .busy_o(busy_o),
    .done_o(done_o),
    .act_buf_wr_en_i(act_buf_wr_en_i),
    .act_buf_wr_addr_i(act_buf_wr_addr_i),
    .act_buf_wr_data_i(act_buf_wr_data_i),
    .weight_buf_wr_en_i(weight_buf_wr_en_i),
    .weight_buf_wr_addr_i(weight_buf_wr_addr_i),
    .weight_buf_wr_data_i(weight_buf_wr_data_i),
    .out_buf_rd_en_i(out_buf_rd_en_i),
    .out_buf_rd_addr_i(out_buf_rd_addr_i),
    .out_buf_rd_data_o(out_buf_rd_data_o)
);

always #5 clk = ~clk;
initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
  end
task load_activation(input int addr, input int a0, input int a1);
    logic signed [DATA_WIDTH-1:0] a0_w;
    logic signed [DATA_WIDTH-1:0] a1_w;
begin
    a0_w = a0;
    a1_w = a1;

    @(posedge clk);
    act_buf_wr_en_i   <= 1;
    act_buf_wr_addr_i <= addr;
    act_buf_wr_data_i <= {a1_w, a0_w};

    @(posedge clk);
    act_buf_wr_en_i   <= 0;

    $display("[%0t] Load Activation k=%0d : A0=%0d A1=%0d packed=%h",
             $time, addr, a0, a1, {a1_w, a0_w});
end
endtask

task load_weight(input int addr, input int w0, input int w1);
    logic signed [DATA_WIDTH-1:0] w0_w;
    logic signed [DATA_WIDTH-1:0] w1_w;
begin
    w0_w = w0;
    w1_w = w1;

    @(posedge clk);
    weight_buf_wr_en_i   <= 1;
    weight_buf_wr_addr_i <= addr;
    weight_buf_wr_data_i <= {w1_w, w0_w};

    @(posedge clk);
    weight_buf_wr_en_i   <= 0;

    $display("[%0t] Load Weight k=%0d : W0=%0d W1=%0d packed=%h",
             $time, addr, w0, w1, {w1_w, w0_w});
end
endtask

always @(posedge clk) begin
    if (dut.u_controller.act_rd_en_o)
        $display("[%0t] Reading activation addr=%0d", $time, dut.u_controller.act_rd_addr_o);

    if (dut.u_controller.weight_rd_en_o)
        $display("[%0t] Reading weight addr=%0d", $time, dut.u_controller.weight_rd_addr_o);

    if (busy_o)
        $display("[%0t] Accelerator running...", $time);

    if (done_o)
        $display("[%0t] Accelerator DONE", $time);
end


initial begin
    clk = 0;
    rst_n = 0;

    start_i = 0;
    k_steps_i = 0;

    act_buf_wr_en_i = 0;
    act_buf_wr_addr_i = 0;
    act_buf_wr_data_i = 0;

    weight_buf_wr_en_i = 0;
    weight_buf_wr_addr_i = 0;
    weight_buf_wr_data_i = 0;

    out_buf_rd_en_i = 0;
    out_buf_rd_addr_i = 0;

    repeat(3) @(posedge clk);
    rst_n = 1;

    $display("======================================");
    $display(" Loading Buffers");
    $display("======================================");

    load_activation(0, 1, 2); // {A[1][0], A[0][0]}
    load_activation(1, 2, 1); // {A[1][1], A[0][1]}

    load_weight(0, 1, 2);     // {B[0][1], B[0][0]}
    load_weight(1, 2, 1);     // {B[1][1], B[1][0]}

    @(posedge clk);
    k_steps_i <= 2;

    $display("======================================");
    $display(" Starting Accelerator");
    $display("======================================");

    @(posedge clk);
    start_i <= 1;
    @(posedge clk);
    start_i <= 0;
    repeat (20) @(posedge clk);
end

initial begin
    wait(done_o);

    @(posedge clk);
    out_buf_rd_addr_i <= 0;
    out_buf_rd_en_i   <= 1;
    repeat (20) @(posedge clk)
    @(posedge clk);
    out_buf_rd_en_i   <= 0;
    repeat (20) @(posedge clk)
    C00 = $signed(out_buf_rd_data_o[0*ACC_WIDTH +: ACC_WIDTH]);
    C01 = $signed(out_buf_rd_data_o[1*ACC_WIDTH +: ACC_WIDTH]);
    C10 = $signed(out_buf_rd_data_o[2*ACC_WIDTH +: ACC_WIDTH]);
    C11 = $signed(out_buf_rd_data_o[3*ACC_WIDTH +: ACC_WIDTH]);

    $display("======================================");
    $display(" Output Matrix C ");
    $display("======================================");
    $display("C00 = %0d", C00);
    $display("C01 = %0d", C01);
    $display("C10 = %0d", C10);
    $display("C11 = %0d", C11);
    $display("======================================");

    if (C00 == 5 && C01 == 4 && C10 == 4 && C11 == 5)
        $display("TEST PASSED");
    else
        $display("TEST FAILED");

    repeat (20) @(posedge clk);
    $finish;
end
// always @(posedge clk) begin
//     $display("[%0t] state=%0d k=%0d act_load=%0b act_fire=%0b w_load_local=%0b pe_w_load=%0b done=%0b",
//         $time,
//         dut.u_controller.state,
//         dut.u_controller.k_index,
//         dut.u_controller.act_local_load_o,
//         dut.u_controller.act_fire_o,
//         dut.u_controller.weight_local_load_o,
//         dut.u_controller.pe_weight_load_o,
//         dut.u_controller.done_o
//     );
// end
// always @(posedge clk) begin
//     $display("[%0t] state=%0d k_index=%0d act_rd_en=%0b w_rd_en=%0b w_valid=%0b act_valid=%0b done=%0b",
//              $time,
//              dut.u_controller.state,
//              dut.u_controller.k_index,
//              dut.u_controller.act_rd_en_o,
//              dut.u_controller.weight_rd_en_o,
//              dut.u_controller.weight_valid_o,
//              dut.u_controller.act_valid_o,
//              dut.u_controller.done_o);
// end
endmodule