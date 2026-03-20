`timescale 1ns / 1ps

module MAC_block_runner #(
   parameter MO_WIDTH = 32,
   parameter ADDR_WIDTH = 10
)
    (
    input  wire                     clk,
    input  wire                     rstn,
	
	input  wire                     start_in,
    input  wire signed [7:0]        Qa_in,
    input  wire signed [7:0]        Qw_in,
    input  wire signed [7:0]        Za_in,
    input  wire signed [7:0]        Zw_in,
    input  wire signed [MO_WIDTH-1:0] M0_in,
    input  wire signed [7:0]        Zo_in,
    input  wire 	   [5:0]        n_in,
    input  wire signed [31:0]       bias_in,
	input  wire        [ADDR_WIDTH-1:0]   Num_in,
	
	output reg  signed [7:0]        result_out,
    output reg                      done,
	output wire                      busy,
	//BRAM ports
	output reg  [ADDR_WIDTH -1:0]   bram_a_addr,
	output reg  [ADDR_WIDTH -1:0]   bram_w_addr
    );
    
    // FSM states
    localparam S_IDLE  = 0;
	localparam S_READY1 = 1;
	localparam S_READY2 = 2;  //BRAM 2-cycle synchronous read
    localparam S_FEED  = 3;   // drive MAC inputs with valid
    localparam S_WAIT  = 4;   // wait for Q3_valid_out
    localparam S_DONE  = 5;
    
	reg start_d = 0;
	wire start_pulse = start_in & ~start_d;  
	
	reg [ADDR_WIDTH:0] idx;
	reg [2:0] state_reg;
	
	// MAC intput driven registers
	reg signed [7:0] reg_Qa, reg_Qw;
    reg signed [7:0] reg_Za, reg_Zw, reg_Zo;
    reg signed [MO_WIDTH-1:0] reg_M0;
    reg [5:0] reg_n;
    reg signed [31:0] reg_bias;
    reg reg_En, reg_clear, reg_last;
	wire signed [7:0] Q3_out_w;
	wire Q3_valid_w;
	
	reg gen_addr = 0; 
	
	assign busy = (state_reg != S_IDLE) && (state_reg != S_DONE);
	
    INT8_MAC_pipelined #(.MO_WIDTH(MO_WIDTH)) mac (
        .CLK(clk), .RST(rstn),
        .Qa_in(reg_Qa), .Qw_in(reg_Qw),
        .Za_in(reg_Za), .Zw_in(reg_Zw),
        .En_in(reg_En),
        .M0_in(reg_M0), .Zo_in(reg_Zo), .n_in(reg_n),
        .bias_in(reg_bias),
        .clear_in(reg_clear),
        .last_in(reg_last),
        .Q3_out(Q3_out_w),
        .Q3_valid_out(Q3_valid_w)
    );
	
	always @(posedge clk or negedge rstn) begin
		if(rstn == 0) begin
			bram_a_addr <= 0;
			bram_w_addr <= 0;
		end
		else if (gen_addr) begin
			bram_a_addr <= bram_a_addr + 1;
			bram_w_addr <= bram_w_addr + 1;
		end
		else begin
		  	bram_a_addr <= 0;
			bram_w_addr <= 0;
		end
		
	end
	// FSM
	always @(posedge clk or negedge rstn) begin
		if(rstn == 0) begin
			state_reg <= S_IDLE;
			reg_En    <= 0;
			reg_clear <= 0;
			reg_last  <= 0;
			start_d <= 0;
			done <= 0;
			idx <= 0;
			gen_addr <= 0;
		end else begin
			//default assigment
			start_d <= start_in;
			reg_En	<= 0;
			reg_last <= 0;
			reg_clear <= 0;
			done <= done;
			case(state_reg)
			S_IDLE: begin
				done <= 0;
				if(start_pulse) begin
	                idx     <= 0;
					gen_addr <= 1;
					state_reg <= S_READY1;
				end
				else state_reg <= S_IDLE;
			end
			S_READY1: begin
				state_reg <= S_READY2;
			end
			S_READY2: begin
				state_reg <= S_FEED;
			end
			S_FEED: begin
				reg_Qa <= $signed(Qa_in);
				reg_Qw <= $signed(Qw_in);
				
				//holding quant params
				reg_Za <= Za_in;
				reg_Zw <= Zw_in;
				reg_Zo <= Zo_in;
				reg_M0 <= M0_in;
				reg_n  <= n_in;
				reg_bias <= bias_in;
				
				reg_En <= 1'b1;
				idx <= idx + 1;
				
				reg_clear <= (idx == 0)? 1'b1: 1'b0;
				reg_last <= (idx == (Num_in -1))? 1'b1: 1'b0;
				
				if (idx == (Num_in -1)) begin
					state_reg <= S_WAIT;
					gen_addr  <= 0;
					idx <= 0;
				end
				else state_reg <= S_FEED;
			end
			S_WAIT: begin
				if(Q3_valid_w) begin
					result_out <= Q3_out_w;
					done <= 1'b1;
					state_reg <= S_DONE;
				end
				else state_reg <= S_WAIT;
			end
			S_DONE: begin
				if(start_pulse) begin
					result_out <= 0;
					done <= 0;
					idx     <= 0;
					gen_addr <= 1;
					state_reg <= S_READY1;
				end
				else state_reg <= S_DONE;
			end
			endcase
		end
	end
	
endmodule
	