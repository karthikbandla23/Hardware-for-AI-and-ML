// ============================================================
// crossbar_mac.sv
// 4x4 Binary-Weight Crossbar MAC Unit
//
// Computes out[j] = sum_i( weight[i][j] * in[i] )
// weight bit = 1 => +1,  weight bit = 0 => -1
//
// Outputs are packed as a flat bus to avoid iverilog
// unpacked-array port limitations:
//   out_flat[ (j+1)*OUT_W-1 : j*OUT_W ] = out[j]
// ============================================================

module crossbar_mac #(
    parameter int N     = 4,
    parameter int IN_W  = 8,
    parameter int OUT_W = 16
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // Input vector packed: in_flat[(i+1)*IN_W-1 : i*IN_W] = in[i]
    input  logic [N*IN_W-1:0]               in_flat,

    // Weight programming
    input  logic                            cfg_we,
    input  logic [$clog2(N)-1:0]            cfg_row,
    input  logic [$clog2(N)-1:0]            cfg_col,
    input  logic                            cfg_wval,

    // Output packed: out_flat[(j+1)*OUT_W-1 : j*OUT_W] = out[j]
    output logic [N*OUT_W-1:0]              out_flat
);

    // Unpack inputs
    logic signed [IN_W-1:0] in_arr [N];
    always_comb begin
        for (int i = 0; i < N; i++)
            in_arr[i] = in_flat[(i+1)*IN_W-1 -: IN_W];
    end

    // Weight register array: weight[row][col]
    logic weight [N][N];

    // Combinational dot product
    logic signed [OUT_W-1:0] dot [N];

    always_comb begin
        for (int j = 0; j < N; j++) begin
            dot[j] = '0;
            for (int i = 0; i < N; i++) begin
                if (weight[i][j])
                    dot[j] = dot[j] + $signed({{(OUT_W-IN_W){in_arr[i][IN_W-1]}}, in_arr[i]});
                else
                    dot[j] = dot[j] - $signed({{(OUT_W-IN_W){in_arr[i][IN_W-1]}}, in_arr[i]});
            end
        end
    end

    // Pack outputs
    always_comb begin
        for (int j = 0; j < N; j++)
            out_flat[(j+1)*OUT_W-1 -: OUT_W] = dot[j];
    end

    // Sequential: weight programming + reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    weight[i][j] <= 1'b1;
        end else begin
            if (cfg_we)
                weight[cfg_row][cfg_col] <= cfg_wval;
        end
    end

endmodule
