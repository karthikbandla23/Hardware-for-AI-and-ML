// weight_regs.sv — 16x27 INT8 weight register file
`timescale 1ns / 1ps
module weight_regs #(
    parameter int DATA_WIDTH   = 8,
    parameter int NUM_FILTERS  = 16,
    parameter int K_TOTAL      = 27
) (
    input  logic                           clk,
    input  logic                           rst,
    input  logic                           wr_en,
    input  logic [$clog2(NUM_FILTERS)-1:0] wr_filter,
    input  logic [$clog2(K_TOTAL)-1:0]     wr_tap,
    input  logic [DATA_WIDTH-1:0]           wr_data,
    output logic [NUM_FILTERS*K_TOTAL*DATA_WIDTH-1:0] weights_flat
);
    // 2D array: mem[filter][tap]
    logic [DATA_WIDTH-1:0] mem [0:NUM_FILTERS-1][0:K_TOTAL-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int f=0; f<NUM_FILTERS; f++)
                for (int t=0; t<K_TOTAL; t++)
                    mem[f][t] <= '0;
        end else if (wr_en) begin
            mem[wr_filter][wr_tap] <= wr_data;
        end
    end

    // Pack to flat output using generate (constant indices only)
    genvar f, t;
    generate
        for (f=0; f<NUM_FILTERS; f++) begin : gf
            for (t=0; t<K_TOTAL; t++) begin : gt
                assign weights_flat[(f*K_TOTAL+t)*DATA_WIDTH +: DATA_WIDTH] = mem[f][t];
            end
        end
    endgenerate
endmodule
