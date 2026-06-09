`timescale 1ns / 1ps

module reg_file #(
    parameter DATA_WIDTH = 17,
    parameter ADDR_WIDTH = 4,
    parameter DEPTH      = 16
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Write Port Synchronous
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    // Read Port Asynchronous
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    // Memory array
    logic [DATA_WIDTH-1:0] registers [0:DEPTH-1];

    // Synchronous Write & Reset 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                registers[i] <= '0;
            end
        end else if (we) begin
            registers[wr_addr] <= wr_data;
        end
    end

    // Asynchronous Read
    assign rd_data = registers[rd_addr];

endmodule