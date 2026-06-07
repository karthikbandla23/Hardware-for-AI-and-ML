// =============================================================================
// mac_array.sv  (M4 final — simple registered tap selection)
// 16 parallel compute_core instances with registered tap-indexed pixel/weight
// =============================================================================
`timescale 1ns / 1ps

module mac_array #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int NUM_FILTERS = 16,
    parameter int K_TOTAL     = KERNEL_SIZE * KERNEL_SIZE * IN_CHANNELS  // 27
) (
    input  logic                                      clk,
    input  logic                                      rst,
    input  logic                                      in_valid,
    input  logic [$clog2(K_TOTAL)-1:0]                tap_idx,
    input  logic [K_TOTAL*DATA_WIDTH-1:0]             pixels_flat,
    input  logic [NUM_FILTERS*K_TOTAL*DATA_WIDTH-1:0] weights_flat,
    output logic [NUM_FILTERS*ACC_WIDTH-1:0]          acc_out_flat,
    output logic                                       done
);

    // Registered tap selection — one cycle latency, but avoids large case mux
    // The FSM's tap_idx is already registered (increments each cycle in S_MAC_RUN)
    // so sel_pixel/sel_weight are stable for the entire compute_core input cycle

    logic [DATA_WIDTH-1:0]       sel_pixel;
    logic [DATA_WIDTH-1:0]       sel_weight [0:NUM_FILTERS-1];

    // Direct array indexing — works correctly in Verilator and synthesis
    // tap_idx is a registered signal so this is purely combinational mux
    always_comb begin
        sel_pixel = pixels_flat[tap_idx * DATA_WIDTH +: DATA_WIDTH];
        for (int f = 0; f < NUM_FILTERS; f++) begin
            sel_weight[f] = weights_flat[(f * K_TOTAL + tap_idx) * DATA_WIDTH +: DATA_WIDTH];
        end
    end

    // 16 compute_core instances, all driven by same pixel/weight
    logic [NUM_FILTERS-1:0] core_done;
    assign done = core_done[0];

    // Module-scope wires for each core output (avoids unpacked array port issue)
    logic signed [ACC_WIDTH-1:0] co0,co1,co2,co3,co4,co5,co6,co7;
    logic signed [ACC_WIDTH-1:0] co8,co9,co10,co11,co12,co13,co14,co15;

    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u0(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[0]),.out(co0),.done(core_done[0]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u1(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[1]),.out(co1),.done(core_done[1]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u2(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[2]),.out(co2),.done(core_done[2]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u3(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[3]),.out(co3),.done(core_done[3]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u4(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[4]),.out(co4),.done(core_done[4]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u5(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[5]),.out(co5),.done(core_done[5]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u6(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[6]),.out(co6),.done(core_done[6]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u7(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[7]),.out(co7),.done(core_done[7]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u8(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[8]),.out(co8),.done(core_done[8]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u9(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[9]),.out(co9),.done(core_done[9]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u10(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[10]),.out(co10),.done(core_done[10]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u11(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[11]),.out(co11),.done(core_done[11]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u12(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[12]),.out(co12),.done(core_done[12]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u13(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[13]),.out(co13),.done(core_done[13]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u14(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[14]),.out(co14),.done(core_done[14]));
    compute_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH),.KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS))
        u15(.clk,.rst,.in_valid,.pixel(sel_pixel),.weight(sel_weight[15]),.out(co15),.done(core_done[15]));

    // Pack outputs
    assign acc_out_flat[0*ACC_WIDTH+:ACC_WIDTH]  = co0;
    assign acc_out_flat[1*ACC_WIDTH+:ACC_WIDTH]  = co1;
    assign acc_out_flat[2*ACC_WIDTH+:ACC_WIDTH]  = co2;
    assign acc_out_flat[3*ACC_WIDTH+:ACC_WIDTH]  = co3;
    assign acc_out_flat[4*ACC_WIDTH+:ACC_WIDTH]  = co4;
    assign acc_out_flat[5*ACC_WIDTH+:ACC_WIDTH]  = co5;
    assign acc_out_flat[6*ACC_WIDTH+:ACC_WIDTH]  = co6;
    assign acc_out_flat[7*ACC_WIDTH+:ACC_WIDTH]  = co7;
    assign acc_out_flat[8*ACC_WIDTH+:ACC_WIDTH]  = co8;
    assign acc_out_flat[9*ACC_WIDTH+:ACC_WIDTH]  = co9;
    assign acc_out_flat[10*ACC_WIDTH+:ACC_WIDTH] = co10;
    assign acc_out_flat[11*ACC_WIDTH+:ACC_WIDTH] = co11;
    assign acc_out_flat[12*ACC_WIDTH+:ACC_WIDTH] = co12;
    assign acc_out_flat[13*ACC_WIDTH+:ACC_WIDTH] = co13;
    assign acc_out_flat[14*ACC_WIDTH+:ACC_WIDTH] = co14;
    assign acc_out_flat[15*ACC_WIDTH+:ACC_WIDTH] = co15;

endmodule
