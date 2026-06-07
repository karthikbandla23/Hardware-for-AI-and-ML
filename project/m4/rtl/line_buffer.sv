// =============================================================================
// line_buffer.sv  (M4 final — single flat array, no reset loop)
// =============================================================================
`timescale 1ns / 1ps

module line_buffer #(
    parameter int DATA_WIDTH  = 8,
    parameter int IMG_W       = 64,
    parameter int IN_CHANNELS = 3,
    parameter int KERNEL_SIZE = 3,
    parameter int K_SPATIAL   = KERNEL_SIZE * KERNEL_SIZE,
    parameter int K_TOTAL     = K_SPATIAL * IN_CHANNELS
) (
    input  logic                             clk,
    input  logic                             rst,
    input  logic                             wr_en,
    input  logic [DATA_WIDTH-1:0]            pixel_in,
    input  logic                             flush_advance,
    output logic [$clog2(IMG_W)-1:0]         col_out,
    output logic [$clog2(IMG_W)-1:0]         row_out,
    output logic                             window_valid,
    output logic [K_TOTAL*DATA_WIDTH-1:0]    window_flat,
    output logic [16:0]                      total_cols_out
);

    localparam int ROW_LEN  = IMG_W * IN_CHANNELS;
    localparam int BUF_SIZE = KERNEL_SIZE * ROW_LEN;

    // Use initial to clear buf_flat (faster than always_ff reset loop)
    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] buf_flat [0:BUF_SIZE-1];

    initial begin
        for (int i = 0; i < BUF_SIZE; i++) buf_flat[i] = '0;
    end

    logic [$clog2(ROW_LEN)-1:0] wr_col_ch;
    logic [1:0]                  wr_row;
    logic [10:0]                 wr_ptr;  // absolute write pointer = wr_row*ROW_LEN + wr_col_ch

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_col_ch <= '0;
            wr_row    <= '0;
            wr_ptr    <= '0;
        end else if (wr_en) begin
            buf_flat[wr_ptr] <= pixel_in;  // no multiplication needed
            if (wr_col_ch == ROW_LEN - 1) begin
                wr_col_ch <= '0;
                if (wr_row == 2) begin
                    wr_row <= '0;
                    wr_ptr <= '0;
                end else begin
                    wr_row <= wr_row + 1;
                    wr_ptr <= wr_ptr + 1;  // increments to next row start
                end
            end else begin
                wr_col_ch <= wr_col_ch + 1;
                wr_ptr    <= wr_ptr + 1;
            end
        end
    end

    // Channel counter — combinational col_advance
    logic [$clog2(IN_CHANNELS)-1:0] ch_cnt;
    always_ff @(posedge clk) begin
        if (rst) ch_cnt <= '0;
        else if (wr_en) ch_cnt <= (ch_cnt == IN_CHANNELS-1) ? '0 : ch_cnt + 1;
    end

    wire col_advance = wr_en && (ch_cnt == IN_CHANNELS - 1);

    // Total columns (registered)
    logic [16:0] total_cols;
    always_ff @(posedge clk) begin
        if (rst) total_cols <= '0;
        else if (col_advance) total_cols <= total_cols + 1;
    end

    // enough_r: registered version of (total_cols >= 2*IMG_W)
    logic enough_r;
    always_ff @(posedge clk) begin
        if (rst) enough_r <= 1'b0;
        else     enough_r <= (total_cols >= 2 * IMG_W);
    end

    assign window_valid = (col_advance && enough_r) || (flush_advance && enough_r);

    // Output position
    logic [$clog2(IMG_W)-1:0] rd_col, rd_row;
    logic [$clog2(IMG_W)-1:0] out_row_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_col      <= '0;
            rd_row      <= '0;
            out_row_cnt <= '0;
        end else if (window_valid) begin
            if (rd_col == IMG_W - 1) begin
                rd_col      <= '0;
                rd_row      <= rd_row + 1;
                out_row_cnt <= out_row_cnt + 1;
            end else begin
                rd_col <= rd_col + 1;
            end
        end
    end

    assign col_out       = rd_col;
    assign row_out       = rd_row;
    assign total_cols_out = total_cols;

    wire top_pad    = (out_row_cnt == 0);
    wire bottom_pad = (out_row_cnt == IMG_W - 1);

    // Row index mapping:
    // wr_row = next row to write = oldest row
    // newest (kr=2) = (wr_row+2)%3, middle (kr=1) = (wr_row+1)%3, oldest (kr=0) = wr_row
    logic [1:0] ri_r0, ri_r1, ri_r2;
    always_comb begin
        case (wr_row)
            2'd0: begin ri_r0=2'd0; ri_r1=2'd1; ri_r2=2'd2; end
            2'd1: begin ri_r0=2'd1; ri_r1=2'd2; ri_r2=2'd0; end
            2'd2: begin ri_r0=2'd2; ri_r1=2'd0; ri_r2=2'd1; end
            default: begin ri_r0=2'd0; ri_r1=2'd1; ri_r2=2'd2; end
        endcase
    end

    // Column offsets from rd_col
    // Use rd_col directly — at posedge when window_flat fires,
    // rd_col still holds pre-NBA value (Verilator deterministic evaluation)
    wire pad_l = (rd_col == 0);
    wire pad_r = (rd_col == IMG_W - 1);

    logic [10:0] c_l [0:IN_CHANNELS-1];
    logic [10:0] c_c [0:IN_CHANNELS-1];
    logic [10:0] c_r [0:IN_CHANNELS-1];

    genvar gch;
    generate
        for (gch = 0; gch < IN_CHANNELS; gch++) begin : gen_coff
            assign c_l[gch] = (rd_col == 0)       ? 0 : (rd_col-1)*IN_CHANNELS + gch;
            assign c_c[gch] = rd_col * IN_CHANNELS + gch;
            assign c_r[gch] = (rd_col == IMG_W-1) ? 0 : (rd_col+1)*IN_CHANNELS + gch;
        end
    endgenerate

    // Row base addresses — case statement avoids signal multiplication
    logic [10:0] b_r0, b_r1, b_r2;
    always_comb begin
        case (ri_r0)
            2'd0: b_r0 = 11'd0;
            2'd1: b_r0 = 11'(ROW_LEN);
            2'd2: b_r0 = 11'(2*ROW_LEN);
            default: b_r0 = 11'd0;
        endcase
        case (ri_r1)
            2'd0: b_r1 = 11'd0;
            2'd1: b_r1 = 11'(ROW_LEN);
            2'd2: b_r1 = 11'(2*ROW_LEN);
            default: b_r1 = 11'd0;
        endcase
        case (ri_r2)
            2'd0: b_r2 = 11'd0;
            2'd1: b_r2 = 11'(ROW_LEN);
            2'd2: b_r2 = 11'(2*ROW_LEN);
            default: b_r2 = 11'd0;
        endcase
    end

    // Window snapshot
    always_ff @(posedge clk) begin
        if (rst) begin
            window_flat <= '0;
        end else if (window_valid) begin
            // ch0 (kr=0 padded if top_pad)
            window_flat[0*DATA_WIDTH  +: DATA_WIDTH] <= (top_pad||pad_l) ? '0 : buf_flat[b_r0+c_l[0]];
            window_flat[1*DATA_WIDTH  +: DATA_WIDTH] <= top_pad ? '0 : buf_flat[b_r0+c_c[0]];
            window_flat[2*DATA_WIDTH  +: DATA_WIDTH] <= (top_pad||pad_r) ? '0 : buf_flat[b_r0+c_r[0]];
            // ch0 kr=1
            window_flat[3*DATA_WIDTH  +: DATA_WIDTH] <= pad_l ? '0 : buf_flat[b_r1+c_l[0]];
            window_flat[4*DATA_WIDTH  +: DATA_WIDTH] <= buf_flat[b_r1+c_c[0]];
            window_flat[5*DATA_WIDTH  +: DATA_WIDTH] <= pad_r ? '0 : buf_flat[b_r1+c_r[0]];
            // ch0 kr=2 (padded if bottom_pad)
            window_flat[6*DATA_WIDTH  +: DATA_WIDTH] <= (bottom_pad||pad_l) ? '0 : buf_flat[b_r2+c_l[0]];
            window_flat[7*DATA_WIDTH  +: DATA_WIDTH] <= bottom_pad ? '0 : buf_flat[b_r2+c_c[0]];
            window_flat[8*DATA_WIDTH  +: DATA_WIDTH] <= (bottom_pad||pad_r) ? '0 : buf_flat[b_r2+c_r[0]];
            // ch1 kr=0
            window_flat[9*DATA_WIDTH  +: DATA_WIDTH] <= (top_pad||pad_l) ? '0 : buf_flat[b_r0+c_l[1]];
            window_flat[10*DATA_WIDTH +: DATA_WIDTH] <= top_pad ? '0 : buf_flat[b_r0+c_c[1]];
            window_flat[11*DATA_WIDTH +: DATA_WIDTH] <= (top_pad||pad_r) ? '0 : buf_flat[b_r0+c_r[1]];
            // ch1 kr=1
            window_flat[12*DATA_WIDTH +: DATA_WIDTH] <= pad_l ? '0 : buf_flat[b_r1+c_l[1]];
            window_flat[13*DATA_WIDTH +: DATA_WIDTH] <= buf_flat[b_r1+c_c[1]];
            window_flat[14*DATA_WIDTH +: DATA_WIDTH] <= pad_r ? '0 : buf_flat[b_r1+c_r[1]];
            // ch1 kr=2
            window_flat[15*DATA_WIDTH +: DATA_WIDTH] <= (bottom_pad||pad_l) ? '0 : buf_flat[b_r2+c_l[1]];
            window_flat[16*DATA_WIDTH +: DATA_WIDTH] <= bottom_pad ? '0 : buf_flat[b_r2+c_c[1]];
            window_flat[17*DATA_WIDTH +: DATA_WIDTH] <= (bottom_pad||pad_r) ? '0 : buf_flat[b_r2+c_r[1]];
            // ch2 kr=0
            window_flat[18*DATA_WIDTH +: DATA_WIDTH] <= (top_pad||pad_l) ? '0 : buf_flat[b_r0+c_l[2]];
            window_flat[19*DATA_WIDTH +: DATA_WIDTH] <= top_pad ? '0 : buf_flat[b_r0+c_c[2]];
            window_flat[20*DATA_WIDTH +: DATA_WIDTH] <= (top_pad||pad_r) ? '0 : buf_flat[b_r0+c_r[2]];
            // ch2 kr=1
            window_flat[21*DATA_WIDTH +: DATA_WIDTH] <= pad_l ? '0 : buf_flat[b_r1+c_l[2]];
            window_flat[22*DATA_WIDTH +: DATA_WIDTH] <= buf_flat[b_r1+c_c[2]];
            window_flat[23*DATA_WIDTH +: DATA_WIDTH] <= pad_r ? '0 : buf_flat[b_r1+c_r[2]];
            // ch2 kr=2
            window_flat[24*DATA_WIDTH +: DATA_WIDTH] <= (bottom_pad||pad_l) ? '0 : buf_flat[b_r2+c_l[2]];
            window_flat[25*DATA_WIDTH +: DATA_WIDTH] <= bottom_pad ? '0 : buf_flat[b_r2+c_c[2]];
            window_flat[26*DATA_WIDTH +: DATA_WIDTH] <= (bottom_pad||pad_r) ? '0 : buf_flat[b_r2+c_r[2]];
        end
    end

endmodule
