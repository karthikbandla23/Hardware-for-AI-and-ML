// =============================================================================
// compute_core.sv
//
// INT8 2D convolution compute core (single MAC unit).
// Project: ECE 410/510 HW4AI Spring 2026 — INT8 Conv2D Accelerator (YOLO layer).
//
// Function:
//   Streams in (pixel, weight) INT8 pairs and accumulates p*w into a signed
//   32-bit register. After K_TOTAL valid pairs have been MAC'd (K_TOTAL =
//   KERNEL_SIZE * KERNEL_SIZE * IN_CHANNELS = 27 for the 3x3x3 YOLO filter),
//   `done` is asserted and `out` holds one output pixel partial sum for one
//   output channel. The accumulator is cleared on the next valid sample after
//   `done`, so back-to-back convolutions can stream without an idle cycle.
//
//   This module is the inner kernel of the full accelerator. In the M3
//   integration, 16 instances of this core run in parallel (one per output
//   filter), fed by a shared 3-row line buffer / window extractor.
//
// Ports
// -----
// clk       in   1   System clock. Single clock domain throughout module.
// rst       in   1   Synchronous, active-high reset. Clears acc, count, done.
// in_valid  in   1   Asserted by upstream when (pixel,weight) is valid this cycle.
// pixel     in   8   Signed INT8 input pixel  (post-quantization activation).
// weight    in   8   Signed INT8 filter weight.
// out       out  32  Signed INT32 accumulated sum-of-products.
// done      out  1   High for one cycle when the K_TOTAL-th MAC has completed;
//                    re-asserts only when another full window has accumulated.
//
// Timing / clocking
// -----------------
//   Single clock domain (clk). All sequential logic uses always_ff @(posedge clk).
//   Reset is synchronous, active-high, asserted relative to clk.
//
// Precision
// ---------
//   pixel, weight: signed 8-bit two's complement.
//   product (internal): signed 16-bit (8x8 -> 16).
//   accumulator / out:  signed 32-bit. ~16 bits of headroom over a single
//   product is sufficient for K_TOTAL=27 INT8 MACs (worst case |sum| <=
//   27 * 127 * 128 = 438,912, fits in 20 bits with sign). See precision.md.
//
// Synthesis notes
// ---------------
//   - All arithmetic operands declared `signed` for correct sign extension.
//   - Product explicitly sign-extended from 16 to 32 bits before accumulation.
//   - No behavioral / non-synthesizable constructs (no #delays, no $display,
//     no file I/O, no dynamic arrays).
// =============================================================================

`timescale 1ns / 1ps

module compute_core #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int K_TOTAL     = KERNEL_SIZE * KERNEL_SIZE * IN_CHANNELS  // 27
) (
    input  logic                          clk,
    input  logic                          rst,
    input  logic                          in_valid,
    input  logic signed [DATA_WIDTH-1:0]  pixel,
    input  logic signed [DATA_WIDTH-1:0]  weight,
    output logic signed [ACC_WIDTH-1:0]   out,
    output logic                          done
);

    // Counter wide enough for K_TOTAL.
    localparam int CNT_WIDTH = $clog2(K_TOTAL + 1);

    logic signed [2*DATA_WIDTH-1:0] pixel_ext;     // sign-extended to 16
    logic signed [2*DATA_WIDTH-1:0] weight_ext;    // sign-extended to 16
    logic signed [2*DATA_WIDTH-1:0] product;       // 16-bit signed p*w
    logic signed [ACC_WIDTH-1:0]    product_ext;   // sign-extended to 32
    logic        [CNT_WIDTH-1:0]    count;

    // Explicitly sign-extend operands BEFORE the multiply so the product is
    // computed in 16-bit context. Verilog's self-determined-context rule for
    // `*` would otherwise truncate the result to the operand width (8 bits)
    // before the LHS-driven width promotion on `product`.
    assign pixel_ext   = (2*DATA_WIDTH)'(pixel);
    assign weight_ext  = (2*DATA_WIDTH)'(weight);
    assign product     = pixel_ext * weight_ext;
    assign product_ext = ACC_WIDTH'(product);

    always_ff @(posedge clk) begin
        if (rst) begin
            out   <= '0;
            count <= '0;
            done  <= 1'b0;
        end else begin
            // Default: done deasserts unless this cycle completes a window.
            done <= 1'b0;

            if (in_valid) begin
                if (done || count == K_TOTAL) begin
                    // Starting a new window: replace, don't accumulate stale acc.
                    out   <= product_ext;
                    count <= CNT_WIDTH'(1);
                end else begin
                    out   <= out + product_ext;
                    count <= count + CNT_WIDTH'(1);
                end

                // Assert done on the cycle the K_TOTAL-th MAC commits.
                if (!done && count == CNT_WIDTH'(K_TOTAL - 1)) begin
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
