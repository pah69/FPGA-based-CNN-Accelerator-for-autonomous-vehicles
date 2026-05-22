`timescale 1ns / 1ps

// Unsigned 6-bit requant shift ROM initialized from a hex memory file.
module requant_shift_rom #(
    parameter int DATA_WIDTH = 6,
    parameter int DEPTH      = 44,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter string INIT_FILE = "small_cnn_sym_requant_shift_u6.mem"
) (
    input logic clk,
    input logic rst_n,

    input  logic [ADDR_WIDTH-1:0] addr_i,
    input  logic                  en_i,
    output logic [DATA_WIDTH-1:0] data_o,
    output logic                  valid_o
);

  (* rom_style = "distributed" *) logic [DATA_WIDTH-1:0] rom_q[0:DEPTH-1];

  initial begin : init_rom
    $readmemh(INIT_FILE, rom_q);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_o  <= '0;
      valid_o <= 1'b0;
    end else begin
      valid_o <= en_i;
      if (en_i) begin
        data_o <= rom_q[addr_i];
      end
    end
  end

endmodule : requant_shift_rom
