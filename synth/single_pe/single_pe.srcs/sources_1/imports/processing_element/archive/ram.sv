////////////////////////////////////////////////////////////////////////////////
// Company: <Company Name>
// Engineer: Anh Ho Pham
//
// Create Date: 03/03/2026
// Design Name: MAC_unit
// Module Name: ram
// Target Device: ZCU104
// Tool versions: Vivado 2025.2
// Description:
//    <Description here>
// Dependencies:
//    <Dependencies here>
// Revision:
//    <Code_revision_information>
// Additional Comments:
//    <Additional_comments>
////////////////////////////////////////////////////////////////////////////////
module ram #(
    parameter DATA_WIDTH = 16
) (
    input logic [DATA_WIDTH-1:0] a,
    input logic [DATA_WIDTH-1:0] b
);

endmodule


// Simple Dual-Port Block RAM with One Clock
// File: simple_dual_one_clock.v

module simple_dual_one_clock (
    clk,
    ena,
    enb,
    wea,
    addra,
    addrb,
    dia,
    dob
);

  input clk, ena, enb, wea;
  input [9:0] addra, addrb;
  input [15:0] dia;
  output [15:0] dob;
  reg [15:0] ram[1023:0];
  reg [15:0] doa, dob;

  always @(posedge clk) begin
    if (ena) begin
      if (wea) begin 
        ram[addra] <= dia;
      end
    end
  end

  always @(posedge clk) begin
    if (enb) begin
        dob <= ram[addrb];
    end
  end

endmodule


module ram_dp_sr_sw (

    clk,        // Clock Input
    address_0,  // address_0 Input
    data_0,     // data_0 bi-directional
    cs_0,       // Chip Select
    we_0,       // Write Enable/Read Enable
    oe_0,       // Output Enable
    address_1,  // address_1 Input
    data_1,     // data_1 bi-directional
    cs_1,       // Chip Select
    we_1,       // Write Enable/Read Enable
    oe_1        // Output Enable
);
  parameter data_0_WIDTH = 8;
  parameter ADDR_WIDTH = 8;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;

  //--------------Input Ports-----------------------
  input [ADDR_WIDTH-1:0] address_0;
  input cs_0;
  input we_0;
  input oe_0;
  input [ADDR_WIDTH-1:0] address_1;
  input cs_1;
  input we_1;
  input oe_1;
  input clk;

  //--------------Inout Ports-----------------------
  inout [data_0_WIDTH-1:0] data_0;
  inout [data_0_WIDTH-1:0] data_1;

  //--------------Internal variables----------------
  reg [data_0_WIDTH-1:0] data_0_out;
  reg [data_0_WIDTH-1:0] data_1_out;
  reg [data_0_WIDTH-1:0] mem[0:RAM_DEPTH-1];
  //--------------Code Starts Here------------------
  // Memory Write Block
  // Write Operation : When we_0 = 1, cs_0 = 1
  always @(posedge clk) begin : MEM_WRITE
    if (cs_0 && we_0) begin
      mem[address_0] <= data_0;
    end else if (cs_1 && we_1) begin
      mem[address_1] <= data_1;
    end
  end

  // Tri-State Buffer control
  // output : When we_0 = 0, oe_0 = 1, cs_0 = 1
  assign data_0 = (cs_0 && oe_0 && !we_0) ? data_0_out : 8'bz;

  // Memory Read Block
  // Read Operation : When we_0 = 0, oe_0 = 1, cs_0 = 1
  always @(posedge clk) begin : MEM_READ_0
    if (cs_0 && !we_0 && oe_0) begin
      data_0_out <= mem[address_0];
    end else begin
      data_0_out <= 0;
    end
  end

  //Second Port of RAM
  // Tri-State Buffer control
  // output : When we_0 = 0, oe_0 = 1, cs_0 = 1
  assign data_1 = (cs_1 && oe_1 && !we_1) ? data_1_out : 8'bz;
  // Memory Read Block 1
  // Read Operation : When we_1 = 0, oe_1 = 1, cs_1 = 1
  always @(posedge clk) begin : MEM_READ_1
    if (cs_1 && !we_1 && oe_1) begin
      data_1_out <= mem[address_1];
    end else begin
      data_1_out <= 0;
    end
  end
endmodule
