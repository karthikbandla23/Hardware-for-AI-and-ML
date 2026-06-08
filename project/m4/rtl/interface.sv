// =============================================================================
// interface.sv
//
// AXI4-Lite (control) + AXI4-Stream (data/result) wrapper for the full
// INT8 Conv2D accelerator.
// Project: ECE 410/510 HW4AI Spring 2026 — INT8 Conv2D Accelerator (YOLO layer).
//
// NOTE ON MODULE NAMING:
//   'interface' is a reserved keyword in SystemVerilog (IEEE 1800-2017 §6.20).
//   The top-level module is named `interface_axi`. A thin alias
//   `interface_wrapper` at the bottom re-exports all ports.
//
// AXI4-Lite register map
// ----------------------
//   0x00  CTRL        RW  [0]=START (self-clears), [1]=WEIGHT_LOAD_DONE
//   0x04  STATUS      RO  [0]=LAYER_DONE, [1]=BUSY
//   0x08  KERNEL_CFG  RW  [7:0]=KERNEL_SIZE, [15:8]=IN_CH, [23:16]=OUT_CH
//   0x0C  RESULT_ROW  RO  current output row (debug)
//   0x10  RESULT_COL  RO  current output col (debug)
//   0x14..0x17  WEIGHT_ADDR RW  [8:0] = {filter[3:0], tap[4:0]} for next write
//   0x18  WEIGHT_DATA RW  [7:0] = INT8 weight; writing triggers weight_regs write
//   0x1C  BIAS_ADDR   RW  [3:0] = filter index for next bias write
//   0x20  BIAS_DATA   RW  [31:0] = INT32 bias; writing triggers bias register write
//
// AXI4-Stream slave (input pixels):
//   TDATA[7:0] = one INT8 pixel per beat (channel-interleaved, row-major)
//   TLAST      = end of input feature map frame
//
// AXI4-Stream master (output results):
//   TDATA[127:0] = 16 x INT8 output pixels packed [filter15..filter0]
//   TLAST        = asserted on last output position of the frame
// =============================================================================

`timescale 1ns / 1ps

module interface_axi #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int NUM_FILTERS = 16,
    parameter int IMG_W       = 64,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32,
    parameter int K_TOTAL     = KERNEL_SIZE * KERNEL_SIZE * IN_CHANNELS  // 27
) (
    input  logic                        clk,
    input  logic                        aresetn,

    // ---- AXI4-Lite slave ----
    input  logic [AXI_ADDR_W-1:0]       s_axi_awaddr,
    input  logic                        s_axi_awvalid,
    output logic                        s_axi_awready,
    input  logic [AXI_DATA_W-1:0]       s_axi_wdata,
    input  logic [AXI_DATA_W/8-1:0]     s_axi_wstrb,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,
    output logic [1:0]                  s_axi_bresp,
    output logic                        s_axi_bvalid,
    input  logic                        s_axi_bready,
    input  logic [AXI_ADDR_W-1:0]       s_axi_araddr,
    input  logic                        s_axi_arvalid,
    output logic                        s_axi_arready,
    output logic [AXI_DATA_W-1:0]       s_axi_rdata,
    output logic [1:0]                  s_axi_rresp,
    output logic                        s_axi_rvalid,
    input  logic                        s_axi_rready,

    // ---- AXI4-Stream slave (input pixels) ----
    input  logic [DATA_WIDTH-1:0]        s_axis_tdata,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,

    // ---- AXI4-Stream master (output: 16 INT8 results packed) ----
    output logic [NUM_FILTERS*DATA_WIDTH-1:0] m_axis_tdata,
    output logic                              m_axis_tvalid,
    input  logic                              m_axis_tready,
    output logic                              m_axis_tlast
);

    logic rst;
    assign rst = ~aresetn;

    // ------------------------------------------------------------------
    // AXI4-Lite register addresses
    // ------------------------------------------------------------------
    localparam logic [7:0] ADDR_CTRL        = 8'h00;
    localparam logic [7:0] ADDR_STATUS      = 8'h04;
    localparam logic [7:0] ADDR_KCFG        = 8'h08;
    localparam logic [7:0] ADDR_RESULT_ROW  = 8'h0C;
    localparam logic [7:0] ADDR_RESULT_COL  = 8'h10;
    localparam logic [7:0] ADDR_WEIGHT_ADDR = 8'h14;
    localparam logic [7:0] ADDR_WEIGHT_DATA = 8'h18;
    localparam logic [7:0] ADDR_BIAS_ADDR   = 8'h1C;
    localparam logic [7:0] ADDR_BIAS_DATA   = 8'h20;

    // ------------------------------------------------------------------
    // Internal registers
    // ------------------------------------------------------------------
    logic [AXI_DATA_W-1:0]  reg_ctrl;
    logic [AXI_DATA_W-1:0]  reg_kcfg;
    logic [8:0]              reg_weight_addr;  // {filter[3:0], tap[4:0]}
    logic [3:0]              reg_bias_addr;

    logic start_pulse;
    logic weight_load_done_reg;

    // ------------------------------------------------------------------
    // Weight and bias storage
    // ------------------------------------------------------------------
    logic                             wgt_wr_en;
    logic [$clog2(NUM_FILTERS)-1:0]   wgt_wr_filter;
    logic [$clog2(K_TOTAL)-1:0]       wgt_wr_tap;
    logic [DATA_WIDTH-1:0]            wgt_wr_data;

    logic [NUM_FILTERS*K_TOTAL*DATA_WIDTH-1:0] weights_flat_w;

    weight_regs #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .K_TOTAL    (K_TOTAL)
    ) u_wgt (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (wgt_wr_en),
        .wr_filter(wgt_wr_filter),
        .wr_tap   (wgt_wr_tap),
        .wr_data       (wgt_wr_data),
        .weights_flat  (weights_flat_w)
    );

    // Bias registers (16 x INT32)
    logic signed [ACC_WIDTH-1:0] bias_regs [0:NUM_FILTERS-1];
    logic                        bias_wr_en;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int f = 0; f < NUM_FILTERS; f++) bias_regs[f] <= '0;
        end else if (bias_wr_en) begin
            bias_regs[reg_bias_addr] <= signed'(s_axi_wdata);
        end
    end

    // ------------------------------------------------------------------
    // AXI4-Lite write FSM
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_t;
    w_state_t w_state;
    logic [AXI_ADDR_W-1:0] aw_addr_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            w_state              <= W_IDLE;
            s_axi_awready        <= 1'b0;
            s_axi_wready         <= 1'b0;
            s_axi_bvalid         <= 1'b0;
            s_axi_bresp          <= 2'b00;
            aw_addr_q            <= '0;
            reg_ctrl             <= '0;
            reg_kcfg             <= {8'd0, 8'(NUM_FILTERS), 8'(IN_CHANNELS), 8'(KERNEL_SIZE)};
            reg_weight_addr      <= '0;
            reg_bias_addr        <= '0;
            start_pulse          <= 1'b0;
            weight_load_done_reg <= 1'b0;
            wgt_wr_en            <= 1'b0;
            bias_wr_en           <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            wgt_wr_en   <= 1'b0;
            bias_wr_en  <= 1'b0;

            unique case (w_state)
                W_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        aw_addr_q     <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        w_state       <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00;
                        case (aw_addr_q[7:0])
                            ADDR_CTRL: begin
                                reg_ctrl <= s_axi_wdata;
                                if (s_axi_wdata[0]) start_pulse          <= 1'b1;
                                if (s_axi_wdata[1]) weight_load_done_reg <= 1'b1;
                            end
                            ADDR_KCFG:        reg_kcfg        <= s_axi_wdata;
                            ADDR_WEIGHT_ADDR: reg_weight_addr <= s_axi_wdata[8:0];
                            ADDR_WEIGHT_DATA: begin
                                wgt_wr_en     <= 1'b1;
                                wgt_wr_filter <= reg_weight_addr[8:5];
                                wgt_wr_tap    <= reg_weight_addr[4:0];
                                wgt_wr_data   <= s_axi_wdata[DATA_WIDTH-1:0];
                            end
                            ADDR_BIAS_ADDR: reg_bias_addr <= s_axi_wdata[3:0];
                            ADDR_BIAS_DATA: bias_wr_en    <= 1'b1;
                            default: s_axi_bresp <= 2'b10;
                        endcase
                        w_state <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase

            if (start_pulse) reg_ctrl[0] <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // AXI4-Lite read FSM
    // ------------------------------------------------------------------
    typedef enum logic [0:0] {R_IDLE, R_DATA} r_state_t;
    r_state_t r_state;

    logic [$clog2(IMG_W)-1:0] out_row, out_col;
    logic busy_w, layer_done_w;

    always_ff @(posedge clk) begin
        if (rst) begin
            r_state       <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= '0;
        end else begin
            unique case (r_state)
                R_IDLE: begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b0;
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready <= 1'b0;
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rresp   <= 2'b00;
                        case (s_axi_araddr[7:0])
                            ADDR_CTRL:       s_axi_rdata <= reg_ctrl;
                            ADDR_STATUS:     s_axi_rdata <= {30'b0, busy_w, layer_done_w};
                            ADDR_KCFG:       s_axi_rdata <= reg_kcfg;
                            ADDR_RESULT_ROW: s_axi_rdata <= {{(AXI_DATA_W - $clog2(IMG_W)){1'b0}}, out_row};
                            ADDR_RESULT_COL: s_axi_rdata <= {{(AXI_DATA_W - $clog2(IMG_W)){1'b0}}, out_col};
                            default: begin
                                s_axi_rdata <= '0;
                                s_axi_rresp <= 2'b10;
                            end
                        endcase
                        r_state <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Line buffer
    // ------------------------------------------------------------------
    logic                        lb_wr_en;
    logic                            lb_window_valid;
    logic [K_TOTAL*DATA_WIDTH-1:0]   lb_window_flat;
    logic [$clog2(IMG_W)-1:0]        lb_col, lb_row;
    logic [16:0]                     lb_total_cols;

    logic pixel_accept;
    logic flush_advance;  // from FSM: advance line_buffer without new pixel

    assign lb_wr_en       = s_axis_tvalid && pixel_accept;
    assign s_axis_tready  = pixel_accept;

    // Detect when all IMG_W*IMG_W columns have been written to the line buffer.
    // total_cols in the line_buffer counts col_advances (= every IN_CHANNELS pixels).
    // When total_cols >= IMG_W*IMG_W, all image pixels have been accepted.
    // Exposed as pixel_in_cnt for debug/testbench visibility.
    logic [16:0] pixel_in_cnt;
    logic        all_pixels_in;
    assign pixel_in_cnt = lb_total_cols;

    always_ff @(posedge clk) begin
        if (rst) begin
            all_pixels_in <= 1'b0;
        end else if (start_pulse) begin
            all_pixels_in <= 1'b0;
        end else if (lb_total_cols >= IMG_W * IMG_W) begin
            all_pixels_in <= 1'b1;
        end
    end

    line_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_W      (IMG_W),
        .IN_CHANNELS(IN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE)
    ) u_lb (
        .clk          (clk),
        .rst          (rst),
        .wr_en        (lb_wr_en),
        .flush_advance(flush_advance),
        .pixel_in     (s_axis_tdata),
        .col_out      (lb_col),
        .row_out      (lb_row),
        .window_valid  (lb_window_valid),
        .window_flat   (lb_window_flat),
        .total_cols_out(lb_total_cols)
    );

    // ------------------------------------------------------------------
    // MAC array
    // ------------------------------------------------------------------
    logic                                         mac_in_valid;
    logic [$clog2(K_TOTAL)-1:0]                   tap_idx;
    logic [NUM_FILTERS*ACC_WIDTH-1:0]             acc_out_flat;
    logic signed [ACC_WIDTH-1:0]                  acc_out [0:NUM_FILTERS-1];
    logic                                         mac_done;

    // Unpack flat output into array for output_pipeline
    always_comb begin
        for (int f = 0; f < NUM_FILTERS; f++)
            acc_out[f] = signed'(acc_out_flat[f*ACC_WIDTH +: ACC_WIDTH]);
    end

    // Flatten lb_window and weights for mac_array
    // pixels_flat = lb_window_flat (direct connection)
    logic [K_TOTAL*DATA_WIDTH-1:0]             pixels_flat;
    // weights_flat comes from weight_regs directly
    logic [NUM_FILTERS*K_TOTAL*DATA_WIDTH-1:0] weights_flat;

    // lb_window_flat IS pixels_flat — direct connection
    assign pixels_flat = lb_window_flat;
    assign weights_flat = weights_flat_w;

    mac_array #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(IN_CHANNELS),
        .NUM_FILTERS(NUM_FILTERS)
    ) u_mac (
        .clk          (clk),
        .rst          (rst),
        .in_valid     (mac_in_valid),
        .tap_idx      (tap_idx),
        .pixels_flat  (pixels_flat),
        .weights_flat (weights_flat),
        .acc_out_flat (acc_out_flat),
        .done         (mac_done)
    );

    // ------------------------------------------------------------------
    // Output pipeline
    // ------------------------------------------------------------------
    logic                          op_valid;
    logic                             op_out_valid;
    logic [NUM_FILTERS*DATA_WIDTH-1:0] op_pixel_out_flat;

    output_pipeline #(
        .ACC_WIDTH  (ACC_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS)
    ) u_op (
        .clk      (clk),
        .rst      (rst),
        .in_valid    (op_valid),
        .acc_in_flat (acc_out_flat),
        .bias_in_flat(bias_regs_flat),
        .out_valid    (op_out_valid),
        .pixel_out_flat(op_pixel_out_flat)
    );

    // ------------------------------------------------------------------
    // Pack bias_regs into flat vector for output_pipeline
    logic [NUM_FILTERS*ACC_WIDTH-1:0] bias_regs_flat;
    assign bias_regs_flat[0*ACC_WIDTH +: ACC_WIDTH] = bias_regs[0];
    assign bias_regs_flat[1*ACC_WIDTH +: ACC_WIDTH] = bias_regs[1];
    assign bias_regs_flat[2*ACC_WIDTH +: ACC_WIDTH] = bias_regs[2];
    assign bias_regs_flat[3*ACC_WIDTH +: ACC_WIDTH] = bias_regs[3];
    assign bias_regs_flat[4*ACC_WIDTH +: ACC_WIDTH] = bias_regs[4];
    assign bias_regs_flat[5*ACC_WIDTH +: ACC_WIDTH] = bias_regs[5];
    assign bias_regs_flat[6*ACC_WIDTH +: ACC_WIDTH] = bias_regs[6];
    assign bias_regs_flat[7*ACC_WIDTH +: ACC_WIDTH] = bias_regs[7];
    assign bias_regs_flat[8*ACC_WIDTH +: ACC_WIDTH] = bias_regs[8];
    assign bias_regs_flat[9*ACC_WIDTH +: ACC_WIDTH] = bias_regs[9];
    assign bias_regs_flat[10*ACC_WIDTH +: ACC_WIDTH] = bias_regs[10];
    assign bias_regs_flat[11*ACC_WIDTH +: ACC_WIDTH] = bias_regs[11];
    assign bias_regs_flat[12*ACC_WIDTH +: ACC_WIDTH] = bias_regs[12];
    assign bias_regs_flat[13*ACC_WIDTH +: ACC_WIDTH] = bias_regs[13];
    assign bias_regs_flat[14*ACC_WIDTH +: ACC_WIDTH] = bias_regs[14];
    assign bias_regs_flat[15*ACC_WIDTH +: ACC_WIDTH] = bias_regs[15];

    // Control FSM
    // ------------------------------------------------------------------
    logic result_drained;
    logic layer_done_flag;

    control_fsm #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_W      (IMG_W),
        .IN_CHANNELS(IN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .NUM_FILTERS(NUM_FILTERS)
    ) u_fsm (
        .clk              (clk),
        .rst              (rst),
        .start_pulse      (start_pulse),
        .weight_load_done (weight_load_done_reg),
        .window_valid     (lb_window_valid),
        .mac_done         (mac_done),
        .result_drained   (result_drained),
        .all_pixels_in    (all_pixels_in),
        .pixel_accept     (pixel_accept),
        .flush_advance    (flush_advance),
        .mac_in_valid     (mac_in_valid),
        .tap_idx          (tap_idx),
        .op_valid         (op_valid),
        .busy             (busy_w),
        .layer_done       (layer_done_w),
        .out_col          (out_col),
        .out_row          (out_row)
    );

    // ------------------------------------------------------------------
    // AXI4-Stream master output
    // Pack 16 INT8 results into 128-bit TDATA
    // ------------------------------------------------------------------
    logic [NUM_FILTERS*DATA_WIDTH-1:0] result_packed;
    logic                              result_pending;
    logic                              is_last_pos;

    localparam int TOTAL_POS = IMG_W * IMG_W;
    logic [16:0] out_pos_cnt;

    // Delay op_out_valid by 1 cycle to let op_pixel_out_flat settle
    logic op_out_valid_r;
    logic [NUM_FILTERS*DATA_WIDTH-1:0] op_pixel_out_flat_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            op_out_valid_r      <= 1'b0;
            op_pixel_out_flat_r <= '0;
        end else begin
            op_out_valid_r      <= op_out_valid;
            op_pixel_out_flat_r <= op_pixel_out_flat;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            result_pending <= 1'b0;
            result_packed  <= '0;
            out_pos_cnt    <= '0;
            is_last_pos    <= 1'b0;
        end else begin
            if (op_out_valid_r) begin
                result_packed  <= op_pixel_out_flat_r;
                result_pending <= 1'b1;
                out_pos_cnt    <= out_pos_cnt + 1;
                is_last_pos    <= (out_pos_cnt == TOTAL_POS - 1);
            end
            if (m_axis_tvalid && m_axis_tready) begin
                result_pending <= 1'b0;
                if (is_last_pos) out_pos_cnt <= '0;
            end
        end
    end

    assign m_axis_tdata   = result_packed;
    assign m_axis_tvalid  = result_pending;
    assign m_axis_tlast   = result_pending && is_last_pos;
    assign result_drained = m_axis_tvalid && m_axis_tready && is_last_pos;

    assign layer_done_flag = layer_done_w;

endmodule

// =============================================================================
// interface_wrapper — thin alias (interface is a reserved SV keyword)
// =============================================================================
module interface_wrapper #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int NUM_FILTERS = 16,
    parameter int IMG_W       = 64,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32
) (
    input  logic                        clk,
    input  logic                        aresetn,
    input  logic [AXI_ADDR_W-1:0]       s_axi_awaddr,
    input  logic                        s_axi_awvalid,
    output logic                        s_axi_awready,
    input  logic [AXI_DATA_W-1:0]       s_axi_wdata,
    input  logic [AXI_DATA_W/8-1:0]     s_axi_wstrb,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,
    output logic [1:0]                  s_axi_bresp,
    output logic                        s_axi_bvalid,
    input  logic                        s_axi_bready,
    input  logic [AXI_ADDR_W-1:0]       s_axi_araddr,
    input  logic                        s_axi_arvalid,
    output logic                        s_axi_arready,
    output logic [AXI_DATA_W-1:0]       s_axi_rdata,
    output logic [1:0]                  s_axi_rresp,
    output logic                        s_axi_rvalid,
    input  logic                        s_axi_rready,
    input  logic [DATA_WIDTH-1:0]        s_axis_tdata,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,
    output logic [NUM_FILTERS*DATA_WIDTH-1:0] m_axis_tdata,
    output logic                              m_axis_tvalid,
    input  logic                              m_axis_tready,
    output logic                              m_axis_tlast
);
    interface_axi #(
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS),
        .NUM_FILTERS(NUM_FILTERS), .IMG_W(IMG_W),
        .AXI_ADDR_W(AXI_ADDR_W), .AXI_DATA_W(AXI_DATA_W)
    ) u (.*);
endmodule
