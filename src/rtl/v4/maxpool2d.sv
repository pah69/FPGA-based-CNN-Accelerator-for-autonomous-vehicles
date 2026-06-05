`timescale 1ns / 1ps

// Channel-major memory-to-memory MaxPool2d, kernel=2, stride=2.
module maxpool2d #(
    parameter int DATA_WIDTH      = 8,
    parameter int BANK_DEPTH      = 8192,
    parameter int ADDR_WIDTH      = (BANK_DEPTH > 1) ? $clog2(BANK_DEPTH) : 1,
    parameter int DIM_WIDTH       = 16,
    parameter int ADDR_CALC_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [3:0] dbg_state_o,
    output logic [DIM_WIDTH-1:0] dbg_channel_o,
    output logic [DIM_WIDTH-1:0] dbg_out_row_o,
    output logic [DIM_WIDTH-1:0] dbg_out_col_o,
    output logic [31:0] dbg_error_code_o,

    input logic read_bank_i,
    input logic write_bank_i,
    input logic [ADDR_WIDTH-1:0] input_base_addr_i,
    input logic [ADDR_WIDTH-1:0] output_base_addr_i,
    input logic [DIM_WIDTH-1:0] in_h_i,
    input logic [DIM_WIDTH-1:0] in_w_i,
    input logic [DIM_WIDTH-1:0] channels_i,
    input logic [DIM_WIDTH-1:0] out_h_i,
    input logic [DIM_WIDTH-1:0] out_w_i,

    output logic                         ub_rd_en_o,
    output logic                         ub_rd_bank_o,
    output logic [ADDR_WIDTH-1:0]        ub_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] ub_rd_data_i,
    input  logic                         ub_rd_valid_i,

    output logic                         ub_wr_en_o,
    output logic                         ub_wr_bank_o,
    output logic [ADDR_WIDTH-1:0]        ub_wr_addr_o,
    output logic signed [DATA_WIDTH-1:0] ub_wr_data_o
);

  typedef enum logic [3:0] {
    S_IDLE,
    S_VALIDATE,
    S_READ_REQ,
    S_READ_WAIT,
    S_WRITE,
    S_ADVANCE,
    S_DONE,
    S_ERROR
  } state_t;

  localparam logic [31:0] ERR_DIMS      = 32'h0004_0001;
  localparam logic [31:0] ERR_READ_ADDR = 32'h0004_0002;
  localparam logic [31:0] ERR_WR_ADDR   = 32'h0004_0003;

  state_t state_q;

  logic read_bank_q;
  logic write_bank_q;
  logic [ADDR_WIDTH-1:0] input_base_addr_q;
  logic [ADDR_WIDTH-1:0] output_base_addr_q;
  logic [DIM_WIDTH-1:0] in_h_q;
  logic [DIM_WIDTH-1:0] in_w_q;
  logic [DIM_WIDTH-1:0] channels_q;
  logic [DIM_WIDTH-1:0] out_h_q;
  logic [DIM_WIDTH-1:0] out_w_q;

  logic [DIM_WIDTH-1:0] channel_q;
  logic [DIM_WIDTH-1:0] out_row_q;
  logic [DIM_WIDTH-1:0] out_col_q;
  logic [1:0] sample_idx_q;
  logic signed [DATA_WIDTH-1:0] max_value_q;

  logic [ADDR_CALC_WIDTH-1:0] in_channel_stride_w;
  logic [ADDR_CALC_WIDTH-1:0] out_channel_stride_w;
  logic [ADDR_CALC_WIDTH-1:0] in_row_w;
  logic [ADDR_CALC_WIDTH-1:0] in_col_w;
  logic [ADDR_CALC_WIDTH-1:0] read_addr_w;
  logic [ADDR_CALC_WIDTH-1:0] write_addr_w;
  logic dims_valid_w;
  logic last_sample_w;
  logic last_out_col_w;
  logic last_out_row_w;
  logic last_channel_w;

  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign dbg_state_o = state_q;
  assign dbg_channel_o = channel_q;
  assign dbg_out_row_o = out_row_q;
  assign dbg_out_col_o = out_col_q;

  assign dims_valid_w = (in_h_q != '0) && (in_w_q != '0) && (channels_q != '0)
                     && (out_h_q != '0) && (out_w_q != '0)
                     && ((ADDR_CALC_WIDTH'(out_h_q) << 1) <= ADDR_CALC_WIDTH'(in_h_q))
                     && ((ADDR_CALC_WIDTH'(out_w_q) << 1) <= ADDR_CALC_WIDTH'(in_w_q));

  assign in_channel_stride_w = ADDR_CALC_WIDTH'(in_h_q) * ADDR_CALC_WIDTH'(in_w_q);
  assign out_channel_stride_w = ADDR_CALC_WIDTH'(out_h_q) * ADDR_CALC_WIDTH'(out_w_q);
  assign in_row_w = (ADDR_CALC_WIDTH'(out_row_q) << 1) + ADDR_CALC_WIDTH'(sample_idx_q[1]);
  assign in_col_w = (ADDR_CALC_WIDTH'(out_col_q) << 1) + ADDR_CALC_WIDTH'(sample_idx_q[0]);

  assign read_addr_w = ADDR_CALC_WIDTH'(input_base_addr_q)
                     + (ADDR_CALC_WIDTH'(channel_q) * in_channel_stride_w)
                     + (in_row_w * ADDR_CALC_WIDTH'(in_w_q))
                     + in_col_w;

  assign write_addr_w = ADDR_CALC_WIDTH'(output_base_addr_q)
                      + (ADDR_CALC_WIDTH'(channel_q) * out_channel_stride_w)
                      + (ADDR_CALC_WIDTH'(out_row_q) * ADDR_CALC_WIDTH'(out_w_q))
                      + ADDR_CALC_WIDTH'(out_col_q);

  assign last_sample_w = (sample_idx_q == 2'd3);
  assign last_out_col_w = ((out_col_q + DIM_WIDTH'(1)) >= out_w_q);
  assign last_out_row_w = ((out_row_q + DIM_WIDTH'(1)) >= out_h_q);
  assign last_channel_w = ((channel_q + DIM_WIDTH'(1)) >= channels_q);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      done_o <= 1'b0;
      error_o <= 1'b0;
      dbg_error_code_o <= '0;
      read_bank_q <= 1'b0;
      write_bank_q <= 1'b1;
      input_base_addr_q <= '0;
      output_base_addr_q <= '0;
      in_h_q <= '0;
      in_w_q <= '0;
      channels_q <= '0;
      out_h_q <= '0;
      out_w_q <= '0;
      channel_q <= '0;
      out_row_q <= '0;
      out_col_q <= '0;
      sample_idx_q <= '0;
      max_value_q <= '0;
      ub_rd_en_o <= 1'b0;
      ub_rd_bank_o <= 1'b0;
      ub_rd_addr_o <= '0;
      ub_wr_en_o <= 1'b0;
      ub_wr_bank_o <= 1'b0;
      ub_wr_addr_o <= '0;
      ub_wr_data_o <= '0;
    end else begin
      done_o <= 1'b0;
      ub_rd_en_o <= 1'b0;
      ub_wr_en_o <= 1'b0;

      unique case (state_q)
        S_IDLE: begin
          error_o <= 1'b0;
          dbg_error_code_o <= '0;
          if (start_i) begin
            read_bank_q <= read_bank_i;
            write_bank_q <= write_bank_i;
            input_base_addr_q <= input_base_addr_i;
            output_base_addr_q <= output_base_addr_i;
            in_h_q <= in_h_i;
            in_w_q <= in_w_i;
            channels_q <= channels_i;
            out_h_q <= out_h_i;
            out_w_q <= out_w_i;
            channel_q <= '0;
            out_row_q <= '0;
            out_col_q <= '0;
            sample_idx_q <= '0;
            max_value_q <= '0;
            state_q <= S_VALIDATE;
          end
        end

        S_VALIDATE: begin
          if (!dims_valid_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_DIMS;
          end else begin
            state_q <= S_READ_REQ;
          end
        end

        S_READ_REQ: begin
          if (read_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH)) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_READ_ADDR;
          end else begin
            ub_rd_en_o <= 1'b1;
            ub_rd_bank_o <= read_bank_q;
            ub_rd_addr_o <= ADDR_WIDTH'(read_addr_w);
            state_q <= S_READ_WAIT;
          end
        end

        S_READ_WAIT: begin
          if (ub_rd_valid_i) begin
            if ((sample_idx_q == 2'd0) || (ub_rd_data_i > max_value_q)) begin
              max_value_q <= ub_rd_data_i;
            end

            if (last_sample_w) begin
              state_q <= S_WRITE;
            end else begin
              sample_idx_q <= sample_idx_q + 2'd1;
              state_q <= S_READ_REQ;
            end
          end
        end

        S_WRITE: begin
          if (write_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH)) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_WR_ADDR;
          end else begin
            ub_wr_en_o <= 1'b1;
            ub_wr_bank_o <= write_bank_q;
            ub_wr_addr_o <= ADDR_WIDTH'(write_addr_w);
            ub_wr_data_o <= max_value_q;
            state_q <= S_ADVANCE;
          end
        end

        S_ADVANCE: begin
          sample_idx_q <= '0;
          max_value_q <= '0;

          if (last_out_col_w) begin
            out_col_q <= '0;
            if (last_out_row_w) begin
              out_row_q <= '0;
              if (last_channel_w) begin
                state_q <= S_DONE;
              end else begin
                channel_q <= channel_q + DIM_WIDTH'(1);
                state_q <= S_READ_REQ;
              end
            end else begin
              out_row_q <= out_row_q + DIM_WIDTH'(1);
              state_q <= S_READ_REQ;
            end
          end else begin
            out_col_q <= out_col_q + DIM_WIDTH'(1);
            state_q <= S_READ_REQ;
          end
        end

        S_DONE: begin
          done_o <= 1'b1;
          if (!start_i) begin
            state_q <= S_IDLE;
          end
        end

        S_ERROR: begin
          error_o <= 1'b1;
        end

        default: begin
          state_q <= S_ERROR;
          error_o <= 1'b1;
          dbg_error_code_o <= ERR_DIMS;
        end
      endcase
    end
  end

endmodule : maxpool2d
