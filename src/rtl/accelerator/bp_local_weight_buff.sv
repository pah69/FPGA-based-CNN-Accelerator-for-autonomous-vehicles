`timescale 1ns / 1ps

module bp_local_weight_buff #(
    parameter int DATA_WIDTH = 17,
    parameter int SIZE       = 32
) (
    input logic clk,
    input logic rst_n,

    // Nhận toàn bộ 544-bit từ RAM thay vì 17-bit
    input  logic [(DATA_WIDTH*SIZE)-1:0] sram_wgt_i, 
    input  logic                         sram_wgt_valid_i,

    // Đẩy 544-bit vào Systolic Array
    output logic [(DATA_WIDTH*SIZE)-1:0] sa_wgt_flatten_o, 
    output logic                         sa_wgt_load_o
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sa_wgt_flatten_o <= '0;
            sa_wgt_load_o    <= 1'b0;
        end else begin
            // Đẩy thẳng qua 1 tầng thanh ghi (Pipeline)
            sa_wgt_flatten_o <= sram_wgt_i;
            // Bắn xung Load mỗi khi có Valid từ Controller
            sa_wgt_load_o    <= sram_wgt_valid_i; 
        end
    end

endmodule

 module fifo #(
    WIDTH = 32,
    DEPTH = 16
 )
 (
    input  logic             clk_i,
    input  logic             rst_n_i,
    //--------------------------------
    // Write
    input  logic [WIDTH-1:0] wdata_i,
    input  logic             wr_en_i,
    output logic             full_o,
    //--------------------------------
    // Read
    output logic [WIDTH-1:0] rdata_o,
    input  logic             rd_en_i,
    output logic             empty_o
 );
    timeunit 1ns; timeprecision 100ps;
    // Check if DEPTH is power of 2
    // Power of 2 means only one bit should be set (e.g. 2=10, 4=100, 8=1000, etc)
    initial begin : depth_power_of_2_check
        assert((DEPTH & (DEPTH-1)) == 0) else
            $error("FIFO depth must be a power of 2");
    end

    localparam ADDR_WIDTH = $clog2(DEPTH);
    logic [ADDR_WIDTH-1:0] rptr, wptr;
    logic full, empty;
    logic last_was_read;

    // Register Array
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Write operation
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wptr <= 0;
        end else begin
            if (wr_en_i && !full) begin
                mem[wptr] <= wdata_i;
                wptr      <= wptr + 1'b1;
            end
        end
    end

    // Read operation
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rptr <= 0;
        end else begin
            if (rd_en_i && !empty) begin
                rptr    <= rptr + 1'b1;
                rdata_o <= mem[rptr];
            end
        end
    end

    // assign rdata_o = mem[rptr];

    // Last operation tracker
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            last_was_read <= 1; // Initialize as empty
        end else begin
            if (rd_en_i && !empty) begin
                last_was_read <= 1;
            end else if (wr_en_i && !full) begin
                last_was_read <= 0;
            end else begin
                last_was_read <= last_was_read;
            end
        end
    end

    assign full    = (wptr == rptr) && !last_was_read; // Last operation was write
    assign empty   = (wptr == rptr) &&  last_was_read; // Last operation was read

    assign full_o  = full;
    assign empty_o = empty;


endmodule : fifo