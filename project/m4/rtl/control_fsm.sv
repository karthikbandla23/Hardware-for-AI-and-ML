// =============================================================================
// control_fsm.sv  (M4 v4)
// =============================================================================
`timescale 1ns / 1ps

module control_fsm #(
    parameter int DATA_WIDTH  = 8,
    parameter int IMG_W       = 64,
    parameter int IN_CHANNELS = 3,
    parameter int KERNEL_SIZE = 3,
    parameter int NUM_FILTERS = 16,
    parameter int K_TOTAL     = KERNEL_SIZE * KERNEL_SIZE * IN_CHANNELS
) (
    input  logic                          clk,
    input  logic                          rst,
    input  logic                          start_pulse,
    input  logic                          weight_load_done,
    input  logic                          window_valid,
    input  logic                          mac_done,
    input  logic                          result_drained,
    input  logic                          all_pixels_in,

    output logic                          pixel_accept,
    output logic                          flush_advance,   // force line_buffer col advance
    output logic                          mac_in_valid,
    output logic [$clog2(K_TOTAL)-1:0]    tap_idx,
    output logic                          op_valid,
    output logic                          busy,
    output logic                          layer_done,
    output logic [$clog2(IMG_W)-1:0]      out_col,
    output logic [$clog2(IMG_W)-1:0]      out_row
);

    typedef enum logic [3:0] {
        S_IDLE        = 4'd0,
        S_FILL        = 4'd1,
        S_FLUSH       = 4'd2,
        S_FLUSH_WAIT  = 4'd3,
        S_WIN_LATCH   = 4'd4,
        S_MAC_RUN     = 4'd5,
        S_ACC_SETTLE  = 4'd6,  // 1-cycle wait for acc_out_flat to settle
        S_OUT_PIPE    = 4'd7,
        S_DONE        = 4'd8
    } state_t;

    state_t state;

    logic [$clog2(K_TOTAL)-1:0]  tap_cnt;
    logic [$clog2(IMG_W)-1:0]    pos_col;
    logic [$clog2(IMG_W)-1:0]    pos_row;
    logic [16:0]                  pos_total;
    logic                         wt_done_latch;
    logic                         in_flush;   // latched: all pixels received

    localparam int TOTAL_POS = IMG_W * IMG_W;

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            tap_cnt      <= '0;
            pos_col      <= '0;
            pos_row      <= '0;
            pos_total    <= '0;
            mac_in_valid <= 1'b0;
            op_valid     <= 1'b0;
            busy         <= 1'b0;
            layer_done   <= 1'b0;
            pixel_accept <= 1'b0;
            flush_advance<= 1'b0;
            wt_done_latch<= 1'b0;
            in_flush     <= 1'b0;
        end else begin
            mac_in_valid  <= 1'b0;
            op_valid      <= 1'b0;
            flush_advance <= 1'b0;

            if (weight_load_done) wt_done_latch <= 1'b1;
            if (all_pixels_in)   in_flush       <= 1'b1;

            unique case (state)

                S_IDLE: begin
                    busy         <= 1'b0;
                    layer_done   <= 1'b0;
                    pos_col      <= '0;
                    pos_row      <= '0;
                    pos_total    <= '0;
                    tap_cnt      <= '0;
                    pixel_accept <= 1'b0;
                    in_flush     <= 1'b0;
                    if (start_pulse && (wt_done_latch || weight_load_done)) begin
                        busy         <= 1'b1;
                        pixel_accept <= 1'b1;
                        wt_done_latch<= 1'b0;
                        state        <= S_FILL;
                    end
                end

                S_FILL: begin
                    // Accept pixels; wait for window_valid or all_pixels_in
                    if (in_flush || all_pixels_in) begin
                        pixel_accept  <= 1'b0;
                        // Issue flush_advance to get next window from buffer
                        flush_advance <= 1'b1;
                        state         <= S_FLUSH;
                    end else begin
                        pixel_accept <= 1'b1;
                        if (window_valid) begin
                            pixel_accept <= 1'b0;
                            tap_cnt      <= '0;
                            state        <= S_WIN_LATCH;
                        end
                    end
                end

                S_FLUSH: begin
                    // Assert flush_advance for 1 cycle to advance line_buffer rd_col
                    flush_advance <= 1'b1;
                    state         <= S_FLUSH_WAIT;
                end

                S_FLUSH_WAIT: begin
                    flush_advance <= 1'b0;
                    tap_cnt       <= '0;
                    state         <= S_WIN_LATCH;
                end

                S_WIN_LATCH: begin
                    // Window data now settled in window_reg; start MAC.
                    tap_cnt      <= '0;
                    mac_in_valid <= 1'b1;
                    state        <= S_MAC_RUN;
                end

                S_MAC_RUN: begin
                    mac_in_valid <= 1'b1;
                    if (tap_cnt == K_TOTAL - 1) begin
                        mac_in_valid <= 1'b0;
                        tap_cnt      <= '0;
                        state        <= S_ACC_SETTLE;
                    end else begin
                        tap_cnt <= tap_cnt + 1;
                    end
                end

                S_ACC_SETTLE: begin
                    // acc_out_flat (registered) now holds completed accumulation
                    state <= S_OUT_PIPE;
                end

                S_OUT_PIPE: begin
                    op_valid  <= 1'b1;
                    pos_total <= pos_total + 1;

                    if (pos_col == IMG_W - 1) begin
                        pos_col <= '0;
                        pos_row <= pos_row + 1;
                    end else begin
                        pos_col <= pos_col + 1;
                    end

                    if (pos_total == TOTAL_POS - 1) begin
                        state <= S_DONE;
                    end else if (in_flush || all_pixels_in) begin
                        state <= S_FLUSH;
                    end else begin
                        pixel_accept <= 1'b1;
                        state        <= S_FILL;
                    end
                end

                S_DONE: begin
                    layer_done   <= 1'b1;
                    pixel_accept <= 1'b0;
                    if (result_drained) begin
                        busy       <= 1'b0;
                        layer_done <= 1'b0;
                        in_flush   <= 1'b0;
                        state      <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign tap_idx = tap_cnt;
    assign out_col = pos_col;
    assign out_row = pos_row;

endmodule
