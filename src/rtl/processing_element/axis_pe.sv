module axis_pe (
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
  logic signed [16:0] s_axis_tdata_reg; // Adjusted from [17:0] to [16:0] to match input DATA_WIDTH=17
  logic s_axis_tvalid_reg;
  logic s_axis_tvalid_tick;
  
  // Pipeline for tlast to match MAC_PIPELINE_DEPTH = 4
  logic [3:0] tlast_pipe;
  
  // 35-bit result wire from PE (2*DATA_WIDTH)
  logic signed [34:0] pe_result;

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
  
  // Backpressure: Ready to receive if the master is ready to accept downstream
  assign s_axis_tready = m_axis_tready;

  // Output tlast is the fully delayed pipeline signal
  assign m_axis_tlast = tlast_pipe[3];

  // Truncate the 35-bit MAC result down to the 17-bit AXI stream data width
  assign m_axis_tdata = pe_result[16:0];

  // --- Processing Element (PE) Instantiation ---
  pe #(
      .DATA_WIDTH        (17),
      .ADDR_WIDTH        (16),
      .MAC_PIPELINE_DEPTH(4)
  ) pe_inst (
      .clk         (aclk),
      .rst_n       (aresetn),
      .activation_i(s_axis_tdata_reg),
      .activation_o(),                 // Unused: Typically chained to the next PE in an array
      .weight_we   (1'b0),             // Tied off: No weight writing logic mapped to this specific AXI stream
      .weight_addr ('0),               // Tied off
      .weight_i    ('0),               // Tied off
      .valid_i     (s_axis_tvalid_reg),
      .start       (s_axis_tvalid_tick), // Start MAC accumulation on the new valid beat
      .acc_clear   (s_axis_tlast),       // Use the incoming tlast to trigger an accumulator clear 
      .valid_o     (m_axis_tvalid),
      .result_o    (pe_result)
  );

endmodule

// module axis_pe (
//     // Global signals
//     input logic aclk,
//     input logic aresetn,

//     // AXI-stream Slave Interface
//     input  logic [16:0] s_axis_tdata,
//     input  logic        s_axis_tvalid,
//     output logic        s_axis_tready,
//     input  logic        s_axis_tlast,

//     // AXI-Stream Master Interface 
//     output logic [16:0] m_axis_tdata,
//     output logic        m_axis_tvalid,
//     input  logic        m_axis_tready,
//     output logic        m_axis_tlast
// );
//   // Registers
//   logic signed [17:0] s_axis_tdata_reg;
//   logic s_axis_tvalid_reg;
//   logic s_axis_tvalid_tick;

//   // Pipeline input
//   always @(posedge aclk) begin
//     if (!aresetn) begin
//       s_axis_tdata_reg <= 0;
//     end else begin
//       s_axis_tdata_reg <= s_axis_tdata;
//     end
//   end

//   // Rising edge detector
//   always @(posedge aclk) begin
//     if (!aresetn) begin
//       s_axis_tvalid_reg <= 0;
//     end else begin
//       s_axis_tvalid_reg <= s_axis_tvalid;
//     end
//   end
//   assign s_axis_tvalid_tick = (s_axis_tvalid) & (~s_axis_tvalid_reg);



//   pe #(
//       .DATA_WIDTH        (17),
//       .ADDR_WIDTH        (16),
//       .MAC_PIPELINE_DEPTH(4)
//   ) pe_inst (
//       .clk         
      
//       (),
//       .rst_n       (),
//       .activation_i(),
//       .activation_o(),
//       .weight_we   (),
//       .weight_addr (),
//       .weight_i    (),
//       .valid_i     (),
//       .start       (),
//       .acc_clear   (),
//       .valid_o     (),
//       .result_o    ()
//   );

// endmodule
