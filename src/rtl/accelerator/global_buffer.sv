`timescale 1ns / 1ps

module bp_global_ram #(
    parameter int DATA_WIDTH = 544, // Mặc định 32 * 17-bit = 544-bit
    parameter int ADDR_WIDTH = 10   // 10 bit địa chỉ = 1024 dòng (sức chứa ~70KB)
) (
    input  logic clk,

    // ========================================
    // Cổng A: Dành cho Host CPU (Ghi dữ liệu vào RAM)
    // ========================================
    input  logic                  ena,    // CPU Enable
    input  logic                  wea,    // CPU Write Enable
    input  logic [ADDR_WIDTH-1:0] addra,  // Địa chỉ từ CPU
    input  logic [DATA_WIDTH-1:0] dina,   // Dữ liệu từ CPU
    output logic [DATA_WIDTH-1:0] douta,  // Dữ liệu trả về CPU (dùng cho Output RAM)

    // ========================================
    // Cổng B: Dành cho NPU Engine (Chỉ đọc cho Input, Chỉ ghi cho Output)
    // ========================================
    input  logic                  enb,    // NPU Enable
    input  logic                  web,    // NPU Write Enable
    input  logic [ADDR_WIDTH-1:0] addrb,  // Địa chỉ từ NPU Controller
    input  logic [DATA_WIDTH-1:0] dinb,   // Dữ liệu từ NPU (khi ghi Output)
    output logic [DATA_WIDTH-1:0] doutb   // Dữ liệu trả về NPU (khi đọc Input)
);

    // Khai báo bộ nhớ vật lý
    logic [DATA_WIDTH-1:0] mem [(2**ADDR_WIDTH)-1:0];

    // Logic Cổng A (Ghi ưu tiên)
    always_ff @(posedge clk) begin
        if (ena) begin
            if (wea) begin
                mem[addra] <= dina;
            end
            douta <= mem[addra];
        end
    end

    // Logic Cổng B
    always_ff @(posedge clk) begin
        if (enb) begin
            if (web) begin
                mem[addrb] <= dinb;
            end
            doutb <= mem[addrb];
        end
    end

endmodule