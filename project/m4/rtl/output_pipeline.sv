// =============================================================================
// output_pipeline.sv
//
// Output pipeline: bias addition, ReLU activation, INT32->INT8 requantization.
// Project: ECE 410/510 HW4AI Spring 2026 — INT8 Conv2D Accelerator (YOLO layer).
//
// Function:
//   For each of 16 output filters:
//     1. Add INT32 bias to INT32 accumulator
//     2. Apply ReLU: max(0, x)
//     3. Requantize: right-shift by SHIFT bits, saturate to INT8 range [-128,127]
//
//   All 16 outputs are computed combinationally in one cycle after the MAC
//   array asserts done. The output is registered before being written to the
//   output buffer.
//
// Parameters:
//   ACC_WIDTH   = 32   accumulator width
//   DATA_WIDTH  = 8    output INT8 width
//   NUM_FILTERS = 16
//   SHIFT       = 8    requantization right-shift (matches S=max(|W|)/127 from M2)
//
// Ports:
//   clk         in   1
//   rst         in   1
//   in_valid    in   1          acc_in and bias_in are valid this cycle
//   acc_in      in   32[16]     INT32 accumulators from mac_array
//   bias_in     in   32[16]     INT32 bias values (loaded via AXI4-Lite)
//   out_valid   out  1          pixel_out is valid next cycle
//   pixel_out   out  8[16]      INT8 output pixels after bias+ReLU+requant
// =============================================================================

`timescale 1ns / 1ps

module output_pipeline #(
    parameter int ACC_WIDTH   = 32,
    parameter int DATA_WIDTH  = 8,
    parameter int NUM_FILTERS = 16,
    parameter int SHIFT       = 8
) (
    input  logic                             clk,
    input  logic                             rst,
    input  logic                             in_valid,
    input  logic [NUM_FILTERS*ACC_WIDTH-1:0]  acc_in_flat,
    input  logic [NUM_FILTERS*ACC_WIDTH-1:0]  bias_in_flat,
    output logic                             out_valid,
    output logic [NUM_FILTERS*DATA_WIDTH-1:0] pixel_out_flat
);

    localparam signed [ACC_WIDTH-1:0] INT8_MAX =  127;
    localparam signed [ACC_WIDTH-1:0] INT8_MIN = -128;

    logic signed [ACC_WIDTH-1:0] biased  [0:NUM_FILTERS-1];
    logic signed [ACC_WIDTH-1:0] relued  [0:NUM_FILTERS-1];
    logic signed [ACC_WIDTH-1:0] shifted [0:NUM_FILTERS-1];
    logic signed [ACC_WIDTH-1:0] sat     [0:NUM_FILTERS-1];

    // Combinational pipeline
    always_comb begin
        for (int f = 0; f < NUM_FILTERS; f++) begin
            // 1. Bias add (unpack from flat inputs)
            biased[f]  = signed'(acc_in_flat[f*ACC_WIDTH +: ACC_WIDTH])
                       + signed'(bias_in_flat[f*ACC_WIDTH +: ACC_WIDTH]);
            // 2. ReLU
            relued[f]  = (biased[f] < 0) ? '0 : biased[f];
            // 3. Right-shift (requantize)
            shifted[f] = relued[f] >>> SHIFT;
            // 4. Saturate to INT8
            if (shifted[f] > INT8_MAX)
                sat[f] = INT8_MAX;
            else if (shifted[f] < INT8_MIN)
                sat[f] = INT8_MIN;
            else
                sat[f] = shifted[f];
        end
    end

    // Register output
    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            pixel_out_flat <= '0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                for (int f = 0; f < NUM_FILTERS; f++)
                    pixel_out_flat[f*DATA_WIDTH +: DATA_WIDTH] <= DATA_WIDTH'(sat[f]);
            end
        end
    end

endmodule
