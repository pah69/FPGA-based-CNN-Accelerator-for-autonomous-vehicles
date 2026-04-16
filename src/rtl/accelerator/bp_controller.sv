`timescale 1ns / 1ps

module controller #(
    parameter DATA_WIDTH         = 17,
    parameter ROWS               = 4,
    parameter COLS               = 4,
    parameter DEPTH              = 256,
    parameter ADDR_WIDTH         = $clog2(DEPTH),
    parameter FINAL_RESULT_DELAY = 5
) (
    input  logic clk,
    input  logic rst_n,

    input  logic start_i,
    input  logic [ADDR_WIDTH:0] k_steps_i,

    input  logic array_all_valid_i,
    input  logic result_valid_i,

    // buffer read controls
    output logic                  act_rd_en_o,
    output logic [ADDR_WIDTH-1:0] act_rd_addr_o,
    output logic                  weight_rd_en_o,
    output logic [ADDR_WIDTH-1:0] weight_rd_addr_o,

    // local_activation controls
    output logic act_local_load_o,
    output logic act_fire_o,
    output logic act_start_fire_o,
    output logic act_clear_fire_o,

    // local_weight controls
    output logic weight_local_load_o,
    output logic pe_weight_load_o,

    // local_output capture
    output logic capture_results_o,

    // output buffer write
    output logic                  out_wr_en_o,
    output logic [ADDR_WIDTH-1:0] out_wr_addr_o,

    output logic busy_o,
    output logic done_o
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_PRE_CLEAR,
        S_ISSUE_READ,
        S_LOAD_LOCAL,
        S_LOAD_PE_WEIGHT,
        S_DRIVE_ACT,
        S_WAIT_FINAL,
        S_CAPTURE,
        S_WRITE_OUT,
        S_DONE
    } state_t;

    state_t state, state_n;

    logic [ADDR_WIDTH:0] k_index, k_index_n;
    logic [7:0]          delay_count, delay_count_n;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            k_index     <= '0;
            delay_count <= '0;
        end else begin
            state       <= state_n;
            k_index     <= k_index_n;
            delay_count <= delay_count_n;
        end
    end

    always_comb begin
        state_n            = state;
        k_index_n          = k_index;
        delay_count_n      = delay_count;

        act_rd_en_o        = 1'b0;
        act_rd_addr_o      = '0;
        weight_rd_en_o     = 1'b0;
        weight_rd_addr_o   = '0;

        act_local_load_o   = 1'b0;
        act_fire_o         = 1'b0;
        act_start_fire_o   = 1'b0;
        act_clear_fire_o   = 1'b0;

        weight_local_load_o = 1'b0;
        pe_weight_load_o    = 1'b0;

        capture_results_o  = 1'b0;

        out_wr_en_o        = 1'b0;
        out_wr_addr_o      = '0;

        busy_o             = 1'b1;
        done_o             = 1'b0;

        case (state)
            S_IDLE: begin
                busy_o = 1'b0;
                if (start_i) begin
                    k_index_n     = '0;
                    delay_count_n = '0;
                    state_n       = S_PRE_CLEAR;
                end
            end

            // clear accumulators as a standalone pulse
            S_PRE_CLEAR: begin
                act_clear_fire_o = 1'b1;
                state_n          = S_ISSUE_READ;
            end

            // request sync RAM reads for current k
            S_ISSUE_READ: begin
                act_rd_en_o      = 1'b1;
                act_rd_addr_o    = k_index[ADDR_WIDTH-1:0];

                weight_rd_en_o   = 1'b1;
                weight_rd_addr_o = k_index[ADDR_WIDTH-1:0];

                state_n          = S_LOAD_LOCAL;
            end

            // load local staging registers from RAM outputs
            S_LOAD_LOCAL: begin
                act_local_load_o    = 1'b1;
                weight_local_load_o = 1'b1;
                state_n             = S_LOAD_PE_WEIGHT;
            end

            // now load PE weight registers from stable local_weight outputs
            S_LOAD_PE_WEIGHT: begin
                pe_weight_load_o = 1'b1;
                state_n          = S_DRIVE_ACT;
            end

            // now fire activations from stable local_activation outputs
            S_DRIVE_ACT: begin
                act_fire_o       = 1'b1;
                act_start_fire_o = (k_index == 0);

                if (k_index + 1 < k_steps_i) begin
                    k_index_n = k_index + 1'b1;
                    state_n   = S_ISSUE_READ;
                end else begin
                    delay_count_n = '0;
                    state_n       = S_WAIT_FINAL;
                end
            end

            S_WAIT_FINAL: begin
                if (delay_count < FINAL_RESULT_DELAY-1) begin
                    delay_count_n = delay_count + 1'b1;
                end else if (array_all_valid_i) begin
                    state_n = S_CAPTURE;
                end
            end

            S_CAPTURE: begin
                capture_results_o = 1'b1;
                state_n           = S_WRITE_OUT;
            end

            S_WRITE_OUT: begin
                if (result_valid_i) begin
                    out_wr_en_o   = 1'b1;
                    out_wr_addr_o = '0;
                    state_n       = S_DONE;
                end
            end

            S_DONE: begin
                busy_o = 1'b0;
                done_o = 1'b1;
                if (!start_i)
                    state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

endmodule