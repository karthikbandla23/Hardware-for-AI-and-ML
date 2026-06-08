// =============================================================================
// tb_top.sv  —  M4 Final Testbench
// Full-layer INT8 Conv2D Accelerator (64x64x3 → 64x64x16)
//
// Uses non-timing Verilator-compatible state machine (no @(posedge clk) in tasks).
// Pixel pipeline: s_tdata is pre-loaded one cycle before s_tvalid is asserted
// to avoid the NBA-ordering duplicate-first-pixel issue in Verilator non-timing mode.
//
// Verified results:
//   pos(0,0) filter0 = 1  (acc=300 >> 8 = 1)
//   pos(0,1) filter0 = 0  (acc=18  >> 8 = 0)
//   pos(1,0) filter0 = 2  (acc=528 >> 8 = 2)
//   beats = 4096/4096, TLAST asserted
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module tb_top;

    localparam int DATA_WIDTH  = 8;
    localparam int ACC_WIDTH   = 32;
    localparam int KERNEL_SIZE = 3;
    localparam int IN_CHANNELS = 3;
    localparam int NUM_FILTERS = 16;
    localparam int IMG_W       = 64;
    localparam int K_TOTAL     = KERNEL_SIZE * KERNEL_SIZE * IN_CHANNELS; // 27
    localparam int TOTAL_PIXELS = IMG_W * IMG_W * IN_CHANNELS;            // 12288
    localparam int TOTAL_OUT    = IMG_W * IMG_W;                           // 4096

    localparam int AXI_ADDR_W  = 32;
    localparam int AXI_DATA_W  = 32;

    // Register offsets
    localparam logic [31:0] ADDR_CTRL        = 32'h00;
    localparam logic [31:0] ADDR_STATUS      = 32'h04;
    localparam logic [31:0] ADDR_WEIGHT_ADDR = 32'h14;
    localparam logic [31:0] ADDR_WEIGHT_DATA = 32'h18;
    localparam logic [31:0] ADDR_BIAS_ADDR   = 32'h1C;
    localparam logic [31:0] ADDR_BIAS_DATA   = 32'h20;

    logic clk = 0, aresetn = 0;
    always #5 clk = ~clk;

    // AXI4-Lite
    logic [AXI_ADDR_W-1:0]    s_axi_awaddr;  logic s_axi_awvalid, s_axi_awready;
    logic [AXI_DATA_W-1:0]    s_axi_wdata;   logic [AXI_DATA_W/8-1:0] s_axi_wstrb;
    logic s_axi_wvalid, s_axi_wready;
    logic [1:0] s_axi_bresp; logic s_axi_bvalid, s_axi_bready;
    logic [AXI_ADDR_W-1:0]    s_axi_araddr;  logic s_axi_arvalid, s_axi_arready;
    logic [AXI_DATA_W-1:0]    s_axi_rdata;   logic [1:0] s_axi_rresp;
    logic s_axi_rvalid, s_axi_rready;

    // AXI4-Stream
    logic [DATA_WIDTH-1:0]              s_axis_tdata;
    logic s_axis_tvalid, s_axis_tready, s_axis_tlast;
    logic [NUM_FILTERS*DATA_WIDTH-1:0]  m_axis_tdata;
    logic m_axis_tvalid, m_axis_tready, m_axis_tlast;

    top #(
        .DATA_WIDTH (DATA_WIDTH), .ACC_WIDTH  (ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),.IN_CHANNELS(IN_CHANNELS),
        .NUM_FILTERS(NUM_FILTERS),.IMG_W      (IMG_W),
        .AXI_ADDR_W (AXI_ADDR_W),.AXI_DATA_W (AXI_DATA_W)
    ) dut (
        .clk            (clk),
        .aresetn        (aresetn),
        .s_axi_awaddr   (s_axi_awaddr),  .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready), .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),   .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),  .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),  .s_axi_bready  (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),  .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready), .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),   .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .s_axis_tdata   (s_axis_tdata),  .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready), .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata),  .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready), .m_axis_tlast  (m_axis_tlast)
    );

    // -----------------------------------------------------------------------
    // Sobel-x weights for all 16 filters (loaded into filter 0 only;
    // filters 1-15 use zero weights from reset).
    // -----------------------------------------------------------------------
    logic signed [7:0] sob_rom [0:K_TOTAL-1];
    initial begin
        for (int ch = 0; ch < IN_CHANNELS; ch++) begin
            sob_rom[ch*9+0] = -1; sob_rom[ch*9+1] =  0; sob_rom[ch*9+2] =  1;
            sob_rom[ch*9+3] = -2; sob_rom[ch*9+4] =  0; sob_rom[ch*9+5] =  2;
            sob_rom[ch*9+6] = -1; sob_rom[ch*9+7] =  0; sob_rom[ch*9+8] =  1;
        end
    end

    // -----------------------------------------------------------------------
    // Pixel function: (row*IMG_W + col + 1 + ch*10) % 128
    // -----------------------------------------------------------------------
    function automatic logic [7:0] pix_f(input int k);
        int ch2, col2, row2;
        ch2  = k % IN_CHANNELS;
        col2 = (k / IN_CHANNELS) % IMG_W;
        row2 = (k / IN_CHANNELS) / IMG_W;
        return 8'((row2 * IMG_W + col2 + 1 + ch2 * 10) % 128);
    endfunction

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    typedef enum logic [3:0] {
        ST_RST     = 4'd0,
        ST_WADDR   = 4'd1,   // write weight address
        ST_WDATA   = 4'd2,   // write weight data
        ST_START   = 4'd3,   // write CTRL (wt_done | start)
        ST_PRELOAD = 4'd4,   // pre-load first pixel into s_axis_tdata
        ST_STREAM  = 4'd5,   // stream pixels
        ST_WAIT    = 4'd6,   // wait for all beats
        ST_DONE    = 4'd7
    } st_t;

    st_t  state    = ST_RST;
    int   cyc      = 0;
    int   pix_sent = 0;
    int   beats    = 0;
    int   widx     = 0;
    int   errors   = 0;
    logic saw_tlast = 0;
    logic [NUM_FILTERS*DATA_WIDTH-1:0] beat0 = '0;
    logic [NUM_FILTERS*DATA_WIDTH-1:0] beat1 = '0;
    logic [NUM_FILTERS*DATA_WIDTH-1:0] beat64= '0;

    always_ff @(posedge clk) begin
        cyc <= cyc + 1;

        // Output beat capture and checking
        if (m_axis_tvalid && m_axis_tready) begin
            if (beats == 0) beat0  <= m_axis_tdata;
            if (beats == 1) beat1  <= m_axis_tdata;
            if (beats == 64) beat64 <= m_axis_tdata;
            beats    <= beats + 1;
            if (m_axis_tlast) saw_tlast <= 1;
            if (beats % 1024 == 0)
                $display("[TB] Progress: beats=%0d/%0d  cyc=%0d", beats, TOTAL_OUT, cyc);
        end

        case (state)
            // ---- Reset ----
            ST_RST: begin
                {s_axi_awvalid, s_axi_wvalid, s_axi_bready} <= 3'b0;
                {s_axi_arvalid, s_axi_rready}               <= 2'b0;
                {s_axis_tvalid, s_axis_tlast}               <= 2'b0;
                s_axi_wstrb <= 4'hF;
                m_axis_tready <= 1'b1;
                if (cyc == 4) begin aresetn <= 1; state <= ST_WADDR; end
            end

            // ---- Load Sobel-x into filter 0 ----
            ST_WADDR: begin
                s_axi_awvalid <= 1;  s_axi_awaddr <= ADDR_WEIGHT_ADDR;
                s_axi_wvalid  <= 1;  s_axi_wdata  <= 32'(widx);  // filter=0, tap=widx
                s_axi_bready  <= 1;
                if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 0;
                if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 0;
                if (s_axi_bvalid  && s_axi_bready)  begin
                    s_axi_bready <= 0;
                    state <= ST_WDATA;
                end
            end

            ST_WDATA: begin
                s_axi_awvalid <= 1;  s_axi_awaddr <= ADDR_WEIGHT_DATA;
                begin
                    logic signed [7:0] w;
                    w = sob_rom[widx];
                    s_axi_wvalid <= 1;  s_axi_wdata <= {{24{w[7]}}, w};
                end
                s_axi_bready <= 1;
                if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 0;
                if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 0;
                if (s_axi_bvalid  && s_axi_bready)  begin
                    s_axi_bready <= 0;
                    if (widx == K_TOTAL - 1) state <= ST_START;
                    else begin widx <= widx + 1; state <= ST_WADDR; end
                end
            end

            // ---- Write CTRL: bit1=wt_done, bit0=start ----
            ST_START: begin
                s_axi_awvalid <= 1;  s_axi_awaddr <= ADDR_CTRL;
                s_axi_wvalid  <= 1;  s_axi_wdata  <= 32'h3;
                s_axi_bready  <= 1;
                if (s_axi_awvalid && s_axi_awready) s_axi_awvalid <= 0;
                if (s_axi_wvalid  && s_axi_wready)  s_axi_wvalid  <= 0;
                if (s_axi_bvalid  && s_axi_bready)  begin
                    s_axi_bready  <= 0;
                    // Pre-load first pixel so it is stable when s_tvalid goes high
                    s_axis_tdata  <= pix_f(0);
                    state         <= ST_PRELOAD;
                end
            end

            // ---- One cycle for s_tdata=pix_f(0) NBA to commit ----
            ST_PRELOAD: begin
                s_axis_tvalid <= 1;
                s_axis_tlast  <= (0 == TOTAL_PIXELS - 1);
                state         <= ST_STREAM;
            end

            // ---- Stream pixels ----
            ST_STREAM: begin
                if (s_axis_tvalid && s_axis_tready) begin
                    pix_sent <= pix_sent + 1;
                    if (pix_sent == TOTAL_PIXELS - 1) begin
                        s_axis_tvalid <= 0;
                        s_axis_tlast  <= 0;
                        state         <= ST_WAIT;
                    end else begin
                        s_axis_tdata <= pix_f(pix_sent + 1);
                        s_axis_tlast <= (pix_sent + 1 == TOTAL_PIXELS - 1);
                    end
                end
            end

            // ---- Wait for remaining output beats (flush rows) ----
            ST_WAIT: begin
                s_axis_tvalid <= 0;
                s_axis_tlast  <= 0;
                if (beats >= TOTAL_OUT || cyc > 600000) state <= ST_DONE;
            end

            // ---- Check results and report ----
            ST_DONE: begin
                $display("[TB] beats=%0d/%0d  tlast=%0b  cyc=%0d",
                         beats, TOTAL_OUT, saw_tlast, cyc);

                // Spot-check three positions against software reference
                $display("[TB] pos(0,0) f0=%0d  exp=1", $signed(beat0[7:0]));
                $display("[TB] pos(0,1) f0=%0d  exp=0", $signed(beat1[7:0]));
                $display("[TB] pos(1,0) f0=%0d  exp=2", $signed(beat64[7:0]));

                if ($signed(beat0[7:0])  !== 8'sd1) begin errors++; $display("[TB] FAIL pos(0,0)"); end
                if ($signed(beat1[7:0])  !== 8'sd0) begin errors++; $display("[TB] FAIL pos(0,1)"); end
                if ($signed(beat64[7:0]) !== 8'sd2) begin errors++; $display("[TB] FAIL pos(1,0)"); end
                if (beats !== TOTAL_OUT)             begin errors++; $display("[TB] FAIL beat count"); end
                if (!saw_tlast)                      begin errors++; $display("[TB] FAIL no TLAST"); end

                if (errors == 0) begin
                    $display("======================================");
                    $display("tb_top: PASS");
                    $display("======================================");
                end else begin
                    $display("======================================");
                    $display("tb_top: FAIL  (%0d errors)", errors);
                    $display("======================================");
                end
                $finish;
            end
        endcase
    end

endmodule
