`timescale 1ns / 1ps

module MAC_IP1 #(  
  parameter integer MO_WIDTH   = 32,
  parameter integer ADDR_WIDTH = 10,
  parameter integer ITE_NUM    = (1 << ADDR_WIDTH) // BRAM depth
)(
  input  wire                      clk,
  input  wire                      rstn,


  // CONTROL (CPU / SoC registers)
  input  wire                      ctrl_start,      
  input  wire [ADDR_WIDTH-1:0]        ctrl_num,        // number of elements to MAC (K)
  input  wire signed [7:0]          ctrl_Za,
  input  wire signed [7:0]          ctrl_Zw,
  input  wire signed [7:0]          ctrl_Zo,
  input  wire signed [MO_WIDTH-1:0] ctrl_M0,
  input  wire [5:0]                ctrl_n,
  input  wire signed [31:0]         ctrl_bias,

  // ACTIVATION BRAM WRITE PORT (CPU)
  input  wire                      act_we,
  input  wire [ADDR_WIDTH-1:0]      act_waddr,
  input  wire signed [7:0]          act_wdata,

  // WEIGHT BRAM WRITE PORT (CPU)
  input  wire                      wgt_we,
  input  wire [ADDR_WIDTH-1:0]      wgt_waddr,
  input  wire signed [7:0]          wgt_wdata,

  // STATUS (CPU reads)
  output wire signed [7:0]          status_result,
  output wire                      status_done,     // sticky done
  output wire                      status_busy

    );
    
    // wires
   wire  [ADDR_WIDTH-1:0] act_raddr;
   wire  [ADDR_WIDTH-1:0] wgt_raddr;
   wire signed [7:0] Qa_bram_q;
   wire signed [7:0] Qw_bram_q;
   
    M10K #(
    .ITE_NUM(ITE_NUM),
    .DATA_WIDTH(8),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) act_bram (
    .q(Qa_bram_q),
    .d(act_wdata),
    .write_address(act_waddr),
    .read_address(act_raddr),
    .we(act_we),
    .clk(clk)
  );

  M10K #(
    .ITE_NUM(ITE_NUM),
    .DATA_WIDTH(8),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) wgt_bram (
    .q(Qw_bram_q),
    .d(wgt_wdata),
    .write_address(wgt_waddr),
    .read_address(wgt_raddr),
    .we(wgt_we),
    .clk(clk)
  );
  
    MAC_block_runner #(
    .MO_WIDTH(MO_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) MAC_core (
    .clk(clk),
    .rstn(rstn),
    .start_in(ctrl_start),

    .Qa_in(Qa_bram_q),
    .Qw_in(Qw_bram_q),
    .Za_in(ctrl_Za),
    .Zw_in(ctrl_Zw),
    .M0_in(ctrl_M0),
    .Zo_in(ctrl_Zo),
    .n_in(ctrl_n),
    .bias_in(ctrl_bias),
    .Num_in(ctrl_num),

    .result_out(status_result),
    .done(status_done),
    .busy(status_busy),
    .bram_a_addr(act_raddr),
    .bram_w_addr(wgt_raddr)
  );


endmodule
