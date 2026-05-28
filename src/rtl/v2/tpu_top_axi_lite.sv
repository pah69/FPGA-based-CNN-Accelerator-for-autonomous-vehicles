`timescale 1ns / 1ps

// Minimal AXI4-Lite control wrapper for tpu_top.
module tpu_top_axi_lite #(
    parameter int AXI_ADDR_WIDTH      = 8,
    parameter int AXI_DATA_WIDTH      = 32,
    parameter int SIZE                = 2,
    parameter int DATA_WIDTH          = 8,
    parameter int ACC_WIDTH           = 32,
    parameter int ACC_DEPTH           = 16,
    parameter int ACC_ADDR_WIDTH      = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int OUT_WIDTH           = 8,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int MAX_NUM_TILES       = 128,
    parameter int TILE_COUNT_WIDTH    = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1,
    parameter int WGT_FIFO_DEPTH      = 16,
    parameter int BANK_DEPTH          = 8192,
    parameter int UB_ADDR_WIDTH       = (BANK_DEPTH > 1) ? $clog2(BANK_DEPTH) : 1
) (
    input logic s_axi_aclk,
    input logic s_axi_aresetn,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    input  logic [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                          s_axi_wvalid,
    output logic                          s_axi_wready,

    output logic [1:0] s_axi_bresp,
    output logic       s_axi_bvalid,
    input  logic       s_axi_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready
);

  localparam logic [7:0] REG_CONTROL     = 8'h00;
  localparam logic [7:0] REG_STATUS      = 8'h04;
  localparam logic [7:0] REG_ERROR       = 8'h08;
  localparam logic [7:0] REG_CYCLES      = 8'h0c;
  localparam logic [7:0] REG_DEBUG0      = 8'h10;
  localparam logic [7:0] REG_DEBUG1      = 8'h14;
  localparam logic [7:0] REG_DEBUG2      = 8'h18;
  localparam logic [7:0] REG_DEBUG3      = 8'h1c;
  localparam logic [7:0] REG_UB_ADDR     = 8'h20;
  localparam logic [7:0] REG_UB_WDATA    = 8'h24;
  localparam logic [7:0] REG_UB_RDATA    = 8'h28;
  localparam logic [7:0] REG_UB_CONTROL  = 8'h2c;

  localparam int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE);

  logic axi_write_fire_w;
  logic axi_read_fire_w;
  logic [7:0] write_addr_w;
  logic [7:0] read_addr_w;
  logic [AXI_DATA_WIDTH-1:0] axi_read_data_w;

  logic start_pulse_q;
  logic overflow_clr_pulse_q;
  logic done_sticky_q;
  logic cmd_error_q;

  logic ub_bank_q;
  logic [UB_ADDR_WIDTH-1:0] ub_addr_q;
  logic signed [DATA_WIDTH-1:0] ub_wdata_q;
  logic signed [DATA_WIDTH-1:0] ub_rdata_q;
  logic ub_rd_valid_q;
  logic ub_host_rd_en_q;
  logic ub_host_wr_en_q;

  logic top_done_w;
  logic top_busy_w;
  logic top_error_w;
  logic [4:0] top_state_w;
  logic [2:0] top_stage_w;
  logic [31:0] top_cycle_count_w;
  logic [31:0] top_error_code_w;
  logic signed [DATA_WIDTH-1:0] top_host_rd_data_w;
  logic top_host_rd_valid_w;
  logic [SIZE*SIZE-1:0] overflow_flatten_w;
  logic [4:0] layer_state_w;
  logic [4:0] layer_tile_state_w;
  logic [15:0] layer_spatial_w;
  logic [15:0] layer_oc_tile_w;
  logic [15:0] layer_k_tile_w;
  logic [3:0] pool_state_w;
  logic [15:0] pool_channel_w;
  logic [15:0] pool_row_w;
  logic [15:0] pool_col_w;

  function automatic logic [AXI_DATA_WIDTH-1:0] apply_wstrb(
      input logic [AXI_DATA_WIDTH-1:0] old_data_i,
      input logic [AXI_DATA_WIDTH-1:0] new_data_i,
      input logic [(AXI_DATA_WIDTH/8)-1:0] strb_i
  );
    logic [AXI_DATA_WIDTH-1:0] result;
    begin
      result = old_data_i;
      for (int byte_idx = 0; byte_idx < (AXI_DATA_WIDTH / 8); byte_idx++) begin
        if (strb_i[byte_idx]) begin
          result[(byte_idx*8)+:8] = new_data_i[(byte_idx*8)+:8];
        end
      end
      apply_wstrb = result;
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH-1:0] sign_extend_i8(
      input logic signed [DATA_WIDTH-1:0] data_i
  );
    begin
      sign_extend_i8 = {{(AXI_DATA_WIDTH-DATA_WIDTH) {data_i[DATA_WIDTH-1]}}, data_i};
    end
  endfunction

  assign s_axi_awready = !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid;
  assign s_axi_wready  = !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid;
  assign s_axi_arready = !s_axi_rvalid;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_rresp   = 2'b00;

  assign axi_write_fire_w = s_axi_awready && s_axi_wready;
  assign axi_read_fire_w  = s_axi_arready && s_axi_arvalid;
  assign write_addr_w     = s_axi_awaddr[7:0];
  assign read_addr_w      = s_axi_araddr[7:0];

  always_comb begin
    axi_read_data_w = '0;

    unique case (read_addr_w)
      REG_CONTROL: begin
        axi_read_data_w[0] = 1'b0;
        axi_read_data_w[1] = 1'b0;
        axi_read_data_w[2] = 1'b0;
      end

      REG_STATUS: begin
        axi_read_data_w[0] = done_sticky_q;
        axi_read_data_w[1] = top_busy_w;
        axi_read_data_w[2] = top_error_w;
        axi_read_data_w[3] = |overflow_flatten_w;
        axi_read_data_w[4] = ub_rd_valid_q;
        axi_read_data_w[5] = cmd_error_q;
        axi_read_data_w[10:8] = top_stage_w;
        axi_read_data_w[16] = top_done_w;
      end

      REG_ERROR: begin
        axi_read_data_w = top_error_code_w;
      end

      REG_CYCLES: begin
        axi_read_data_w = top_cycle_count_w;
      end

      REG_DEBUG0: begin
        axi_read_data_w[4:0] = top_state_w;
        axi_read_data_w[10:8] = top_stage_w;
        axi_read_data_w[20:16] = layer_state_w;
        axi_read_data_w[28:24] = layer_tile_state_w;
      end

      REG_DEBUG1: begin
        axi_read_data_w[15:0] = layer_spatial_w;
        axi_read_data_w[31:16] = layer_oc_tile_w;
      end

      REG_DEBUG2: begin
        axi_read_data_w[15:0] = layer_k_tile_w;
        axi_read_data_w[31:16] = pool_channel_w;
      end

      REG_DEBUG3: begin
        axi_read_data_w[15:0] = pool_row_w;
        axi_read_data_w[31:16] = pool_col_w;
      end

      REG_UB_ADDR: begin
        axi_read_data_w[UB_ADDR_WIDTH-1:0] = ub_addr_q;
        axi_read_data_w[31] = ub_bank_q;
      end

      REG_UB_WDATA: begin
        axi_read_data_w = sign_extend_i8(ub_wdata_q);
      end

      REG_UB_RDATA: begin
        axi_read_data_w[DATA_WIDTH-1:0] = ub_rdata_q;
        axi_read_data_w[8] = ub_rd_valid_q;
      end

      REG_UB_CONTROL: begin
        axi_read_data_w[0] = 1'b0;
        axi_read_data_w[1] = 1'b0;
        axi_read_data_w[8] = ub_rd_valid_q;
      end

      default: begin
        axi_read_data_w = '0;
      end
    endcase
  end

  tpu_top #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .LOCAL_PSUM_WIDTH   (LOCAL_PSUM_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .WGT_FIFO_DEPTH     (WGT_FIFO_DEPTH),
      .BANK_DEPTH         (BANK_DEPTH),
      .UB_ADDR_WIDTH      (UB_ADDR_WIDTH)
  ) u_tpu_top (
      .clk                   (s_axi_aclk),
      .rst_n                 (s_axi_aresetn),
      .start_i               (start_pulse_q),
      .done_o                (top_done_w),
      .busy_o                (top_busy_w),
      .error_o               (top_error_w),
      .dbg_state_o           (top_state_w),
      .dbg_stage_o           (top_stage_w),
      .dbg_cycle_count_o     (top_cycle_count_w),
      .dbg_error_code_o      (top_error_code_w),
      .host_rd_en_i          (ub_host_rd_en_q),
      .host_rd_bank_i        (ub_bank_q),
      .host_rd_addr_i        (ub_addr_q),
      .host_rd_data_o        (top_host_rd_data_w),
      .host_rd_valid_o       (top_host_rd_valid_w),
      .host_wr_en_i          (ub_host_wr_en_q),
      .host_wr_bank_i        (ub_bank_q),
      .host_wr_addr_i        (ub_addr_q),
      .host_wr_data_i        (ub_wdata_q),
      .overflow_clr_i        (overflow_clr_pulse_q),
      .overflow_flatten_o    (overflow_flatten_w),
      .dbg_layer_state_o     (layer_state_w),
      .dbg_layer_tile_state_o(layer_tile_state_w),
      .dbg_layer_spatial_o   (layer_spatial_w),
      .dbg_layer_oc_tile_o   (layer_oc_tile_w),
      .dbg_layer_k_tile_o    (layer_k_tile_w),
      .dbg_pool_state_o      (pool_state_w),
      .dbg_pool_channel_o    (pool_channel_w),
      .dbg_pool_row_o        (pool_row_w),
      .dbg_pool_col_o        (pool_col_w)
  );

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_bvalid        <= 1'b0;
      s_axi_rvalid        <= 1'b0;
      s_axi_rdata         <= '0;
      start_pulse_q       <= 1'b0;
      overflow_clr_pulse_q <= 1'b0;
      done_sticky_q       <= 1'b0;
      cmd_error_q         <= 1'b0;
      ub_bank_q           <= 1'b0;
      ub_addr_q           <= '0;
      ub_wdata_q          <= '0;
      ub_rdata_q          <= '0;
      ub_rd_valid_q       <= 1'b0;
      ub_host_rd_en_q     <= 1'b0;
      ub_host_wr_en_q     <= 1'b0;
    end else begin
      start_pulse_q        <= 1'b0;
      overflow_clr_pulse_q <= 1'b0;
      ub_host_rd_en_q      <= 1'b0;
      ub_host_wr_en_q      <= 1'b0;

      if (top_done_w) begin
        done_sticky_q <= 1'b1;
      end

      if (top_host_rd_valid_w) begin
        ub_rdata_q <= top_host_rd_data_w;
        ub_rd_valid_q <= 1'b1;
      end

      if (axi_write_fire_w) begin
        s_axi_bvalid <= 1'b1;

        unique case (write_addr_w)
          REG_CONTROL: begin
            if (s_axi_wdata[2]) begin
              done_sticky_q <= 1'b0;
              cmd_error_q <= 1'b0;
              ub_rd_valid_q <= 1'b0;
            end

            if (s_axi_wdata[1]) begin
              overflow_clr_pulse_q <= 1'b1;
            end

            if (s_axi_wdata[0]) begin
              if (!top_busy_w) begin
                start_pulse_q <= 1'b1;
                done_sticky_q <= 1'b0;
                cmd_error_q <= 1'b0;
              end else begin
                cmd_error_q <= 1'b1;
              end
            end
          end

          REG_UB_ADDR: begin
            logic [AXI_DATA_WIDTH-1:0] merged_addr;
            merged_addr = apply_wstrb({{(AXI_DATA_WIDTH-UB_ADDR_WIDTH-1){1'b0}}, ub_bank_q, ub_addr_q},
                                      s_axi_wdata, s_axi_wstrb);
            ub_addr_q <= merged_addr[UB_ADDR_WIDTH-1:0];
            ub_bank_q <= merged_addr[31];
          end

          REG_UB_WDATA: begin
            if (s_axi_wstrb[0]) begin
              ub_wdata_q <= s_axi_wdata[DATA_WIDTH-1:0];
            end
          end

          REG_UB_CONTROL: begin
            if (s_axi_wdata[0]) begin
              if (!top_busy_w) begin
                ub_host_wr_en_q <= 1'b1;
              end else begin
                cmd_error_q <= 1'b1;
              end
            end

            if (s_axi_wdata[1]) begin
              if (!top_busy_w) begin
                ub_host_rd_en_q <= 1'b1;
                ub_rd_valid_q <= 1'b0;
              end else begin
                cmd_error_q <= 1'b1;
              end
            end
          end

          default: begin
          end
        endcase
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (axi_read_fire_w) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rdata <= axi_read_data_w;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end

endmodule : tpu_top_axi_lite
