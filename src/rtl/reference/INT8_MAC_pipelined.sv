`timescale 1ns/1ps

module INT8_MAC_pipelined #(
    parameter MO_WIDTH = 32
)(
    input  wire                     CLK,
    input  wire                     RST,

    input  wire signed [7:0]        Qa_in,
    input  wire signed [7:0]        Qw_in,
    input  wire signed [7:0]        Za_in,
    input  wire signed [7:0]        Zw_in,
    input  wire                     En_in,

    input  wire signed [MO_WIDTH-1:0] M0_in,
    input  wire signed [7:0]        Zo_in,
    input  wire 	   [5:0]        n_in,

    input  wire signed [31:0]       bias_in,
    input  wire                     clear_in,
    input  wire                     last_in,

    output reg  signed [7:0]        Q3_out,
    output reg                      Q3_valid_out
);

localparam integer FRAC_BITS = (MO_WIDTH - 1);




// stage0 registers
reg v0;
reg signed [7:0] s0_Qa, s0_Qw, s0_Za, s0_Zw;
reg signed [MO_WIDTH-1:0] s0_M0;
reg 	   [5:0] s0_n;
reg signed [7:0] s0_Zo;
reg signed [31:0] s0_bias;
reg s0_clear, s0_last;

//stage 0: Latch input
always @(posedge CLK or negedge RST) begin
	if (RST == 0) begin
		v0 <= 0;
		s0_Qa <= 0;
		s0_Qw <= 0;   
		s0_Za <= 0;
		s0_Zw <= 0;
		s0_M0 <= 0;
		s0_n <= 0;
		s0_Zo <= 0;
		s0_bias <= 0;
		s0_clear <= 0;
		s0_last <= 0;
	end else begin
		v0 <= En_in;
		if (En_in) begin
		s0_Qa <= Qa_in;
		s0_Qw <= Qw_in; 
		s0_Za <= Za_in;
		s0_Zw <= Zw_in;
		s0_M0 <= M0_in;
		s0_n <= n_in;
		s0_Zo <= Zo_in;
		s0_bias <= bias_in;
		s0_clear <= clear_in;
		s0_last <= last_in;
		end
	end
end

//stage1 registers
reg v1;
reg signed [8:0] s1_a_off, s1_w_off;
reg [5:0] s1_n;
reg signed [MO_WIDTH -1: 0] s1_M0;
reg signed [31:0] s1_bias;
reg signed [7:0]  s1_Zo;
reg s1_clear, s1_last;
//stage 1: subtract Zero-point
always @(posedge CLK or negedge RST) begin
	if (RST == 0) begin
		v1 <= 0;
		s1_a_off <= 0;
		s1_w_off <= 0; 
		s1_M0 <= 0;
		s1_n <= 0;
		s1_Zo <= 0;
		s1_bias <= 0;
		s1_clear <= 0;
		s1_last <= 0;
	end else begin
		v1 <= v0;
		if (v0) begin
			s1_a_off <= $signed({s0_Qa[7], s0_Qa}) - $signed({s0_Za[7],s0_Za});
			s1_w_off <= $signed({s0_Qw[7],s0_Qw}) - $signed({s0_Zw[7], s0_Zw}); 
			s1_M0 <= s0_M0;
			s1_n <= s0_n;
			s1_Zo <= s0_Zo;
			s1_bias <= s0_bias;
			s1_clear <= s0_clear;
			s1_last <= s0_last;
		end
	end
end

// stage2 registers
reg v2;
reg signed [17:0] s2_prod;
reg [5:0] s2_n;
reg signed [MO_WIDTH -1: 0] s2_M0;
reg signed [31:0] s2_bias;
reg signed [7:0]  s2_Zo;
reg s2_clear, s2_last;
//stage 2: Multiply
always @(posedge CLK or negedge RST) begin
	if (RST == 0) begin
		v2 <= 0;
		s2_prod <= 0;
		s2_M0 <= 0;
		s2_n <= 0;
		s2_Zo <= 0;
		s2_bias <= 0;
		s2_clear <= 0;
		s2_last <= 0;
	end else begin
		v2 <= v1;
		if (v1) begin
			s2_prod <= s1_a_off * s1_w_off;
			s2_M0 <= s1_M0;
			s2_n <= s1_n;
			s2_Zo <= s1_Zo;
			s2_bias <= s1_bias;
			s2_clear <= s1_clear;
			s2_last <= s1_last;
		end
	end
end

// stage3 registers
reg v3;
reg signed  [31:0] s3_acc;
reg [5:0] s3_n;
reg signed [MO_WIDTH -1: 0] s3_M0;
reg signed [31:0] s3_bias;
reg signed [7:0]  s3_Zo;
reg s3_last;
//stage3: accumulate
always @(posedge CLK or negedge RST) begin
	if (RST == 0) begin
		v3 <= 0;
		s3_acc <= 0;
		s3_M0 <= 0;
		s3_n <= 0;
		s3_Zo <= 0;
		s3_bias <= 0;
		s3_last <= 0;
	end else begin
		v3 <= v2;
		if (v2) begin
			if(s2_clear) s3_acc <= $signed({{14{s2_prod[17]}},s2_prod});
			else 		 s3_acc <= s3_acc + $signed({{14{s2_prod[17]}},s2_prod});
			s3_M0 <= s2_M0;
			s3_n <= s2_n;
			s3_Zo <= s2_Zo;
			s3_bias <= s2_bias;
			s3_last <= s2_last;
		end
		else s3_last <= 0;
	end
end

// stage4 registers
reg v4;
reg signed [63:0] s4_mul_M;
reg [5:0] s4_n;
reg signed [7:0]  s4_Zo;
// stage4: Add bias and requant Multiply
always @(posedge CLK or negedge RST) begin
	if(RST == 0) begin
		v4 <= 0;
		s4_mul_M <= 0;
		s4_n <= 0;
		s4_Zo <= 0;
	end
	else begin 
		v4 <= (v3 & s3_last);
		if (v3 && s3_last) begin
			s4_mul_M   <= $signed(s3_M0) * $signed(s3_acc + s3_bias);
			s4_n <= s3_n;
			s4_Zo <= s3_Zo;
		end
	end
end

//stage5: Rounding and shift right
reg v5;
reg signed [31:0] s5_roundedProd;
reg signed [7:0]  s5_Zo;

wire [7:0] sh_full = FRAC_BITS + s4_n;
wire [5:0] shift_amt = (sh_full > 8'd63) ? 6'd63 : sh_full;

wire signed [63:0] round_add =
  (shift_amt == 0) ? 64'sd0 :
  (s4_mul_M >= 0 ?  (64'sd1 <<< (shift_amt-1))
                    : ((64'sd1 <<< (shift_amt-1)) - 1));

wire signed [63:0] scaledF =
  (shift_amt == 0) ? s4_mul_M
                   : ((s4_mul_M + round_add) >>> shift_amt);
				   
always @(posedge CLK or negedge RST) begin
	if(RST == 0) begin
		v5 <= 0;
		s5_roundedProd <= 0;
		s5_Zo <= 0;
	end
	else begin 
		v5 <= v4;
		if (v4) begin
			s5_roundedProd <= $signed(scaledF[31:0]);
			s5_Zo <= s4_Zo;
		end
	end
end

//stag6: Add Zo and Saturation
wire signed [31:0] zo_ext = $signed({{24{s5_Zo[7]}}, s5_Zo}); 
wire signed [32:0] raw_result = zo_ext + $signed(s5_roundedProd);
always @(posedge CLK or negedge RST) begin
	if(RST == 0) begin
		Q3_out <= 0;
		Q3_valid_out <= 0;
	end
	else begin
		if (v5) begin
			Q3_valid_out <= 1;
			if (raw_result > 127) 
				Q3_out <= 8'sd127;
			else if (raw_result < -128)
				Q3_out <= -8'sd128;
			else Q3_out <= $signed(raw_result[7:0]);
		end else begin
			Q3_valid_out <= 0;
			Q3_out <= 0;
		end
	end
end 

endmodule