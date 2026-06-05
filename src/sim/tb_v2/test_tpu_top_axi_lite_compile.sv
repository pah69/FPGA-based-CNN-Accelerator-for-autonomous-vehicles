`timescale 1ns / 1ps

module test_tpu_top_axi_lite_compile;

  localparam int AXI_ADDR_WIDTH = 8;
  localparam int AXI_DATA_WIDTH = 32;

  logic clk;
  logic rst_n;

  logic [AXI_ADDR_WIDTH-1:0] awaddr;
  logic awvalid;
  logic awready;
  logic [AXI_DATA_WIDTH-1:0] wdata;
  logic [(AXI_DATA_WIDTH/8)-1:0] wstrb;
  logic wvalid;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [AXI_ADDR_WIDTH-1:0] araddr;
  logic arvalid;
  logic arready;
  logic [AXI_DATA_WIDTH-1:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;

  tpu_top_axi_lite #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) u_tpu_top_axi_lite (
      .s_axi_aclk   (clk),
      .s_axi_aresetn(rst_n),
      .s_axi_awaddr (awaddr),
      .s_axi_awvalid(awvalid),
      .s_axi_awready(awready),
      .s_axi_wdata  (wdata),
      .s_axi_wstrb  (wstrb),
      .s_axi_wvalid (wvalid),
      .s_axi_wready (wready),
      .s_axi_bresp  (bresp),
      .s_axi_bvalid (bvalid),
      .s_axi_bready (bready),
      .s_axi_araddr (araddr),
      .s_axi_arvalid(arvalid),
      .s_axi_arready(arready),
      .s_axi_rdata  (rdata),
      .s_axi_rresp  (rresp),
      .s_axi_rvalid (rvalid),
      .s_axi_rready (rready)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '1;
    wvalid = 1'b0;
    bready = 1'b1;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b1;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    $finish;
  end

endmodule : test_tpu_top_axi_lite_compile
