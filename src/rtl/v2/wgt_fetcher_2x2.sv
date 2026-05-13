`timescale 1ns / 1ps

module wgt_fetcher_2x2 #(
    parameter int SIZE       = 2,
    parameter int DATA_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    input  logic start_load_i,
    output logic ready_o,

    // Giao tiếp với FIFO (Đã sửa cho Synchronous FIFO có trễ 1 nhịp)
    input  logic [(DATA_WIDTH*SIZE)-1:0] fifo_data_i,
    input  logic                         fifo_empty_i,
    output logic                         fifo_pop_o, // Nối với rd_en_i của FIFO

    // Giao tiếp với Systolic Array
    output logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_o,
    output logic        [SIZE-1:0]              wgt_load_o,
    output logic                                weight_switch_o
);

    typedef enum logic [2:0] {
        IDLE,
        READ_1, // Trạng thái phát lệnh đọc đầu tiên
        PUMP_1, // Nhận dữ liệu hàng 1 và phát lệnh đọc hàng 0
        PUMP_0, // Nhận dữ liệu hàng 0
        SWITCH  // Chốt trọng số
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start_load_i && !fifo_empty_i) next_state = READ_1;
            end
            READ_1: begin
                next_state = PUMP_1;
            end
            PUMP_1: begin
                next_state = PUMP_0;
            end
            PUMP_0: begin
                next_state = SWITCH;
            end
            SWITCH: begin
                next_state = IDLE;
            end
        endcase
    end

    always_comb begin
        // Giá trị mặc định
        ready_o         = 1'b0;
        fifo_pop_o      = 1'b0;
        wgt_flatten_o   = '0;
        wgt_load_o      = '0;
        weight_switch_o = 1'b0;

        case (state)
            IDLE: begin
                ready_o = 1'b1;
            end
            READ_1: begin
                // Phát tín hiệu xin đọc hàng dưới cùng (Hàng 1)
                fifo_pop_o = 1'b1; 
            end
            PUMP_1: begin
                // Dữ liệu hàng 1 đã có sẵn ở cổng ra của FIFO
                wgt_flatten_o = fifo_data_i;  
                wgt_load_o    = {SIZE{1'b1}}; 
                
                // Đồng thời phát tín hiệu xin đọc hàng trên (Hàng 0)
                fifo_pop_o = 1'b1; 
            end
            PUMP_0: begin
                // Dữ liệu hàng 0 đã có sẵn
                wgt_flatten_o = fifo_data_i;
                wgt_load_o    = {SIZE{1'b1}};
            end
            SWITCH: begin
                weight_switch_o = 1'b1;
            end
        endcase
    end
endmodule