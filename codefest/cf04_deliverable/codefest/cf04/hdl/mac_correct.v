// mac_correct.v
// Corrected 8-bit signed multiply-accumulate unit
// - Signed operands and accumulator
// - Synchronous active-high reset
// - always_ff for sequential logic
// - Explicit sign extension of the 16-bit product to 32 bits

module mac (
    input  logic               clk,
    input  logic               rst,
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    output logic signed [31:0] out
);

    logic signed [15:0] product;
    logic signed [31:0] product_ext;

    // Combinational multiply, then explicit sign extension to 32 bits
    assign product     = a * b;
    assign product_ext = {{16{product[15]}}, product};

    always_ff @(posedge clk) begin
        if (rst)
            out <= 32'sd0;
        else
            out <= out + product_ext;
    end

endmodule
