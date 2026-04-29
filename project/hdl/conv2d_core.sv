// conv2d_core.v
// Project compute core - top-level module for 2D convolution accelerator
//
// Computes one output pixel of a 2D convolution per accumulation cycle:
//
//     out_pixel = sum over (i,j) in [0..K-1] x [0..K-1] of
//                     pixel[i,j] * weight[i,j]
//
// Inputs are streamed in element-by-element (one pixel-weight pair per
// valid cycle) and accumulated in a signed 32-bit register. After
// KERNEL_SIZE*KERNEL_SIZE valid pairs have been consumed, `done` is asserted
// and `out` holds the convolution sum for that output position.
//
// This is the inner kernel of the conv layer; an outer datapath (or the
// host/SPI controller) is responsible for sliding the kernel window across
// the input feature map and presenting the (pixel, weight) pairs in order.
//
// Constraints applied (from CF04 CLLM lessons):
//   - All arithmetic operands declared signed
//   - always_ff for sequential logic
//   - Synchronous active-high reset
//   - Explicit sign extension of the 16-bit product to 32 bits

module conv2d_core #(
    parameter int DATA_WIDTH   = 8,                     // INT8 pixels & weights
    parameter int ACC_WIDTH    = 32,                    // signed accumulator width
    parameter int KERNEL_SIZE  = 3                      // K x K convolution kernel
) (
    input  logic                                clk,
    input  logic                                rst,         // active-high sync
    input  logic                                in_valid,    // pixel/weight pair valid
    input  logic signed [DATA_WIDTH-1:0]        pixel,       // input pixel
    input  logic signed [DATA_WIDTH-1:0]        weight,      // kernel weight
    output logic signed [ACC_WIDTH-1:0]         out,         // accumulated sum
    output logic                                done         // one output pixel ready
);

    localparam int N_TAPS = KERNEL_SIZE * KERNEL_SIZE;

    // Element counter -- how many MACs since reset
    logic [$clog2(N_TAPS+1)-1:0] count;

    // Sign-extended product
    logic signed [2*DATA_WIDTH-1:0]  product;
    logic signed [ACC_WIDTH-1:0]     product_ext;

    assign product     = pixel * weight;
    assign product_ext = {{(ACC_WIDTH - 2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};

    always_ff @(posedge clk) begin
        if (rst) begin
            out   <= '0;
            count <= '0;
            done  <= 1'b0;
        end
        else if (in_valid && !done) begin
            out   <= out + product_ext;
            count <= count + 1'b1;
            done  <= (count == N_TAPS - 1);
        end
    end

endmodule
