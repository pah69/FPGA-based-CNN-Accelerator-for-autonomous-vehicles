module axis_pe (
    // Global Signals
    input logic aclk,
    input logic aresetn,

    // AXI-Stream Slave Interface (Input Data)
    input  logic [16:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    // AXI-Stream Master Interface (Output Result)
    output logic [16:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

  logic signed [17:0] s_axis_tdata_reg;
  logic s_axis_tvalid_reg;
  logic s_axis_tvalid_tick;


  // Pipeline input
  always @(posedge aclk) begin
    if (!aresetn) begin
      s_axis_tdata_reg <= 0;
    end else begin
      s_axis_tdata_reg <= s_axis_tdata;
    end
  end

  // Rising edge detector
  always @(posedge aclk) begin
    if (!aresetn) begin
      s_axis_tvalid_reg <= 0;
    end else begin
      s_axis_tvalid_reg <= s_axis_tvalid;
    end
  end
  assign s_axis_tvalid_tick = s_axis_tvalid & ~s_axis_tvalid_reg;


  pe #(
      .DATA_WIDTH        (17),
      .ADDR_WIDTH        (16),
      .MAC_PIPELINE_DEPTH(4)
  ) pe_inst (
      .clk         (),
      .rst_n       (),
      .activation_i(),
      .activation_o(),
      .weight_we   (),
      .weight_addr (),
      .weight_i    (),
      .valid_i     (),
      .start       (),
      .acc_clear   (),
      .valid_o     (),
      .result_o    ()
  );

endmodule
