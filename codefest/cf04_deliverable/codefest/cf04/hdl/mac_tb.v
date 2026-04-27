// mac_tb.v
// Testbench for the mac module
// Stimulus per CF04 spec:
//   [a=3, b=4]  for 3 cycles
//   assert rst
//   [a=-5, b=2] for 2 cycles

`timescale 1ns/1ps

module mac_tb;

    logic               clk;
    logic               rst;
    logic signed [7:0]  a;
    logic signed [7:0]  b;
    logic signed [31:0] out;

    // DUT
    mac dut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .out(out)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // VCD dump for GTKWave
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, mac_tb);
    end

    initial begin
        // Init + initial reset
        rst = 1;
        a   = 8'sd0;
        b   = 8'sd0;
        @(posedge clk); #1;
        rst = 0;
        $display("after reset    : out = %0d (expect 0)", out);

        // Phase 1: a=3, b=4 for 3 cycles -> 12, 24, 36
        a = 8'sd3;
        b = 8'sd4;
        @(posedge clk); #1;
        $display("cycle 1 (3*4)  : out = %0d (expect 12)", out);
        @(posedge clk); #1;
        $display("cycle 2 (3*4)  : out = %0d (expect 24)", out);
        @(posedge clk); #1;
        $display("cycle 3 (3*4)  : out = %0d (expect 36)", out);

        // Assert rst
        rst = 1;
        @(posedge clk); #1;
        $display("after rst pulse: out = %0d (expect 0)", out);
        rst = 0;

        // Phase 2: a=-5, b=2 for 2 cycles -> -10, -20
        a = -8'sd5;
        b =  8'sd2;
        @(posedge clk); #1;
        $display("cycle 4 (-5*2) : out = %0d (expect -10)", out);
        @(posedge clk); #1;
        $display("cycle 5 (-5*2) : out = %0d (expect -20)", out);

        // Pass/fail summary
        if (out === -32'sd20)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL  (final out = %0d, expected -20)", out);

        $finish;
    end

endmodule
