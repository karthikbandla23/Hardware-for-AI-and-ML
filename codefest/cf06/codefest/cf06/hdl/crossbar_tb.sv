// ============================================================
// crossbar_tb.sv
// Testbench for crossbar_mac — 4x4 Binary-Weight MAC Unit
//
// Weight matrix:
//   W = [[ 1, -1,  1, -1],   row 0
//        [ 1,  1, -1, -1],   row 1
//        [-1,  1,  1, -1],   row 2
//        [-1, -1, -1,  1]]   row 3
//
// Input vector: [10, 20, 30, 40]
//
// Hand-computed expected outputs:
//   out[0] =  1(10) + 1(20) + (-1)(30) + (-1)(40) = 10+20-30-40 = -40
//   out[1] = (-1)(10) + 1(20) + 1(30) + (-1)(40)  = -10+20+30-40 =  0
//   out[2] =  1(10) + (-1)(20) + 1(30) + (-1)(40) = 10-20+30-40  = -20
//   out[3] = (-1)(10) + (-1)(20) + (-1)(30) + 1(40)= -10-20-30+40= -20
// ============================================================

`timescale 1ns/1ps

module crossbar_tb;

    localparam int N     = 4;
    localparam int IN_W  = 8;
    localparam int OUT_W = 16;

    // DUT signals
    logic                       clk;
    logic                       rst_n;
    logic [N*IN_W-1:0]          in_flat;
    logic                       cfg_we;
    logic [$clog2(N)-1:0]       cfg_row;
    logic [$clog2(N)-1:0]       cfg_col;
    logic                       cfg_wval;
    logic [N*OUT_W-1:0]         out_flat;

    // DUT
    crossbar_mac #(.N(N), .IN_W(IN_W), .OUT_W(OUT_W)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .in_flat (in_flat),
        .cfg_we  (cfg_we),
        .cfg_row (cfg_row),
        .cfg_col (cfg_col),
        .cfg_wval(cfg_wval),
        .out_flat(out_flat)
    );

    // Helper functions to pack/unpack
    function automatic logic [IN_W-1:0] get_in(input int i);
        get_in = in_flat[(i+1)*IN_W-1 -: IN_W];
    endfunction

    function automatic logic signed [OUT_W-1:0] get_out(input int j);
        get_out = out_flat[(j+1)*OUT_W-1 -: OUT_W];
    endfunction

    task automatic set_in(input int i, input logic signed [IN_W-1:0] val);
        in_flat[(i+1)*IN_W-1 -: IN_W] = val;
    endtask

    // Clock — 10 ns period
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // Weight programming task
    task automatic set_weight(input int row, col, input logic wval);
        @(negedge clk);
        cfg_row  = row[$clog2(N)-1:0];
        cfg_col  = col[$clog2(N)-1:0];
        cfg_wval = wval;
        cfg_we   = 1'b1;
        @(negedge clk);
        cfg_we   = 1'b0;
    endtask

    // Test variables
    logic signed [OUT_W-1:0] expected [N];
    integer pass_count, fail_count;

    initial begin
        // Initialise
        rst_n    = 1'b1;
        cfg_we   = 1'b0;
        cfg_row  = '0;
        cfg_col  = '0;
        cfg_wval = 1'b0;
        in_flat  = '0;
        pass_count = 0;
        fail_count = 0;

        // Reset pulse
        @(negedge clk); rst_n = 1'b0;
        repeat(2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // --------------------------------------------------
        // Program weight matrix
        // W[row][col]:
        //   row0: +1 -1 +1 -1  =>  1 0 1 0
        //   row1: +1 +1 -1 -1  =>  1 1 0 0
        //   row2: -1 +1 +1 -1  =>  0 1 1 0
        //   row3: -1 -1 -1 +1  =>  0 0 0 1
        // --------------------------------------------------
        $display("=== Programming Weight Matrix ===");
        $display("W = [[ 1,-1, 1,-1],");
        $display("     [ 1, 1,-1,-1],");
        $display("     [-1, 1, 1,-1],");
        $display("     [-1,-1,-1, 1]]");

        set_weight(0,0, 1'b1); set_weight(0,1, 1'b0);
        set_weight(0,2, 1'b1); set_weight(0,3, 1'b0);

        set_weight(1,0, 1'b1); set_weight(1,1, 1'b1);
        set_weight(1,2, 1'b0); set_weight(1,3, 1'b0);

        set_weight(2,0, 1'b0); set_weight(2,1, 1'b1);
        set_weight(2,2, 1'b1); set_weight(2,3, 1'b0);

        set_weight(3,0, 1'b0); set_weight(3,1, 1'b0);
        set_weight(3,2, 1'b0); set_weight(3,3, 1'b1);

        // --------------------------------------------------
        // Apply input [10, 20, 30, 40]
        // --------------------------------------------------
        $display("\n=== Applying Input Vector [10, 20, 30, 40] ===");
        @(negedge clk);
        set_in(0, 8'sd10);
        set_in(1, 8'sd20);
        set_in(2, 8'sd30);
        set_in(3, 8'sd40);

        // Wait 1 cycle for combinational to settle
        @(posedge clk); #1;

        // --------------------------------------------------
        // Hand-computed expected values
        // --------------------------------------------------
        expected[0] = -16'sd40;
        expected[1] =  16'sd0;
        expected[2] = -16'sd20;
        expected[3] = -16'sd20;

        // --------------------------------------------------
        // Check results
        // --------------------------------------------------
        $display("\n=== Simulation Results ===");
        $display("out[j]   Expected   Got    Status");
        $display("----------------------------------");

        for (int j = 0; j < N; j++) begin
            if (get_out(j) === expected[j]) begin
                $display("out[%0d]    %4d      %4d   PASS", j, expected[j], get_out(j));
                pass_count++;
            end else begin
                $display("out[%0d]    %4d      %4d   FAIL <<<", j, expected[j], get_out(j));
                fail_count++;
            end
        end

        $display("----------------------------------");
        $display("Total: %0d PASS  %0d FAIL", pass_count, fail_count);

        if (fail_count == 0) begin
            $display("\ncrossbar_tb PASSED: all outputs match hand-computed values.");
        end else begin
            $fatal(1, "crossbar_tb FAILED: %0d mismatches.", fail_count);
        end

        $finish;
    end

endmodule
