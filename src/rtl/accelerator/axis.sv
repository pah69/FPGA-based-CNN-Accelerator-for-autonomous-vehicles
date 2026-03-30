module axis (
    // Global signals
    input logic aclk,
    input logic aresetn,

    // AXI-stream Slave Interface
    input  logic [16:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    // AXI-Stream Master Interface 
    output logic [16:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

  // Registers
  logic signed [16:0] s_axis_tdata_reg;
  logic s_axis_tvalid_reg;
  logic s_axis_tvalid_tick;
  
  // Pipeline for tlast to match MAC_PIPELINE_DEPTH = 4
  logic [3:0] tlast_pipe;
  
  // 35-bit result wire from PE (2*DATA_WIDTH)

  // Pipeline input and tlast shift register
  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      s_axis_tdata_reg <= '0;
      tlast_pipe       <= '0;
    end else begin
      // Sample data when handshaking is successful
      if (s_axis_tvalid && s_axis_tready) begin
        s_axis_tdata_reg <= s_axis_tdata;
        tlast_pipe       <= {tlast_pipe[2:0], s_axis_tlast};
      end else begin
        // Shift 0s into tlast if no valid data is passing through
        tlast_pipe       <= {tlast_pipe[2:0], 1'b0};
      end
    end
  end

  // Rising edge detector for valid signal
  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      s_axis_tvalid_reg <= 1'b0;
    end else if (s_axis_tready) begin
      s_axis_tvalid_reg <= s_axis_tvalid;
    end
  end
  assign s_axis_tvalid_tick = (s_axis_tvalid) & (~s_axis_tvalid_reg);

  // --- AXI-Stream Protocol Logic ---

endmodule
