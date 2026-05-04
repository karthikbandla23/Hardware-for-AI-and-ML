// =============================================================================
// interface.sv
//
// AXI4-Lite (control) + AXI4-Stream (data) wrapper around compute_core.
// Project: ECE 410/510 HW4AI Spring 2026 — INT8 Conv2D Accelerator (YOLO layer).
//
// NOTE ON MODULE NAMING:
//   The file is named interface.sv per the M2 checklist requirement. However,
//   'interface' is a reserved keyword in SystemVerilog (IEEE 1800-2017 §6.20)
//   and cannot be used as a module name. The top-level module is therefore
//   named `interface_axi`. A thin alias module `interface_wrapper` at the
//   bottom of this file re-exports all ports and instantiates `interface_axi`,
//   allowing both names to compile cleanly.
//
// This module is the interface chosen in M1 (project/m1/interface_selection.md):
//   - AXI4-Lite for control registers (status, layer config, start/done).
//   - AXI4-Stream for the (pixel, weight) data path into the MAC, and for the
//     32-bit accumulator output to the host.
//
// Single clock domain (s_axi_aclk = s_axis_aclk = m_axis_aclk = clk). Single
// synchronous active-low reset (aresetn) consistent with AXI convention; the
// internal compute_core uses an active-high synchronous reset, generated as
// `~aresetn`.
//
// AXI4-Lite register map (4 x 32-bit, byte-addressable, word-aligned)
// -----------------------------------------------------------------
//   Offset  Name        Access  Description
//   0x00    CTRL        RW      [0]   START   — write 1 to launch (self-clears)
//                               [1]   IRQ_EN  — interrupt enable (loopback)
//                               [31:2] reserved
//   0x04    STATUS      RO      [0]   DONE    — high while result is valid
//                               [1]   BUSY    — high while compute_core active
//                               [31:2] reserved
//   0x08    KERNEL_CFG  RW      [7:0]   KERNEL_SIZE (informational)
//                               [15:8]  IN_CHANNELS (informational)
//                               [23:16] OUT_CHANNELS (informational)
//   0x0C    RESULT      RO      Last completed accumulator value (signed 32).
//
// Address decoding uses bits [3:2] (4-word aperture). Higher address bits are
// ignored within this stub; full system integration uses the platform's
// AXI interconnect for address space partitioning.
//
// AXI4-Stream contract
// --------------------
//   Slave (input)  s_axis: TVALID/TREADY handshake. TDATA[15:8] = weight,
//                  TDATA[7:0] = pixel (both INT8). TLAST is accepted but
//                  ignored — the K_TOTAL counter inside compute_core handles
//                  framing. The slave deasserts TREADY when the compute_core
//                  is not ready to accept (i.e. between START write and the
//                  first beat, or after DONE while RESULT has not been
//                  consumed by m_axis).
//   Master (output) m_axis: TVALID/TREADY handshake. TDATA[31:0] = signed
//                  accumulator. TLAST is asserted with each emitted beat
//                  (one-result-per-frame).
//
// Protocol notes (per AMBA AXI4-Stream spec, A3.1):
//   - TVALID may not depend on TREADY (no combinational loop).
//   - Once TVALID is asserted it must remain asserted until the handshake
//     completes (TVALID && TREADY).
//   - TREADY may be asserted before TVALID.
//
// AXI4-Lite handshake (AMBA AXI4-Lite spec, B1):
//   - All five channels (AW, W, B, AR, R) use VALID/READY pairs.
//   - Write response BRESP = 2'b00 (OKAY) on a successful aligned write.
//   - Read response RRESP  = 2'b00 (OKAY).
//   - Unaligned or out-of-range accesses return BRESP/RRESP = 2'b10 (SLVERR).
// =============================================================================

`timescale 1ns / 1ps

module interface_axi #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32
) (
    input  logic                       clk,
    input  logic                       aresetn,   // active-low, synchronous

    // ---------------- AXI4-Lite slave (control) ----------------
    input  logic [AXI_ADDR_W-1:0]      s_axi_awaddr,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,
    input  logic [AXI_DATA_W-1:0]      s_axi_wdata,
    input  logic [AXI_DATA_W/8-1:0]    s_axi_wstrb,
    input  logic                       s_axi_wvalid,
    output logic                       s_axi_wready,
    output logic [1:0]                 s_axi_bresp,
    output logic                       s_axi_bvalid,
    input  logic                       s_axi_bready,
    input  logic [AXI_ADDR_W-1:0]      s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,
    output logic [AXI_DATA_W-1:0]      s_axi_rdata,
    output logic [1:0]                 s_axi_rresp,
    output logic                       s_axi_rvalid,
    input  logic                       s_axi_rready,

    // ---------------- AXI4-Stream slave (input data) ----------------
    // TDATA[15:8] = weight (INT8), TDATA[7:0] = pixel (INT8)
    input  logic [15:0]                s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,

    // ---------------- AXI4-Stream master (output result) ----------------
    output logic [ACC_WIDTH-1:0]       m_axis_tdata,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast
);

    // ------------------------------------------------------------------
    // Register map
    // ------------------------------------------------------------------
    localparam logic [3:0] ADDR_CTRL   = 4'h0;
    localparam logic [3:0] ADDR_STATUS = 4'h4;
    localparam logic [3:0] ADDR_KCFG   = 4'h8;
    localparam logic [3:0] ADDR_RESULT = 4'hC;

    logic [AXI_DATA_W-1:0] reg_ctrl;
    logic [AXI_DATA_W-1:0] reg_status;
    logic [AXI_DATA_W-1:0] reg_kcfg;
    logic [AXI_DATA_W-1:0] reg_result;

    // Convenience strobes
    logic start_pulse;
    logic core_done;
    logic core_busy;

    // ------------------------------------------------------------------
    // AXI4-Lite write FSM (AW, W, B channels)
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_t;
    w_state_t w_state;

    logic [AXI_ADDR_W-1:0] aw_addr_q;

    always_ff @(posedge clk) begin
        if (!aresetn) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_addr_q     <= '0;
            reg_ctrl      <= '0;
            reg_kcfg      <= {8'd0, 8'd1, 8'(IN_CHANNELS), 8'(KERNEL_SIZE)};
            start_pulse   <= 1'b0;
        end else begin
            start_pulse <= 1'b0;  // pulse — clears every cycle by default

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
                        s_axi_bresp  <= 2'b00;  // OKAY by default
                        case (aw_addr_q[3:0])
                            ADDR_CTRL: begin
                                reg_ctrl <= s_axi_wdata;
                                if (s_axi_wdata[0]) start_pulse <= 1'b1;
                            end
                            ADDR_KCFG: reg_kcfg <= s_axi_wdata;
                            ADDR_STATUS, ADDR_RESULT: begin
                                // Read-only — write succeeds but is ignored
                                // (could elect SLVERR; keeping OKAY for ease
                                // of host-side use).
                            end
                            default: s_axi_bresp <= 2'b10;  // SLVERR — bad addr
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

            // CTRL.START is a self-clearing bit
            if (start_pulse) reg_ctrl[0] <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // AXI4-Lite read FSM (AR, R channels)
    // ------------------------------------------------------------------
    typedef enum logic [0:0] {R_IDLE, R_DATA} r_state_t;
    r_state_t r_state;

    always_ff @(posedge clk) begin
        if (!aresetn) begin
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
                        case (s_axi_araddr[3:0])
                            ADDR_CTRL:   s_axi_rdata <= reg_ctrl;
                            ADDR_STATUS: s_axi_rdata <= reg_status;
                            ADDR_KCFG:   s_axi_rdata <= reg_kcfg;
                            ADDR_RESULT: s_axi_rdata <= reg_result;
                            default: begin
                                s_axi_rdata <= '0;
                                s_axi_rresp <= 2'b10; // SLVERR
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
    // STATUS register (combinational view of internal state)
    // ------------------------------------------------------------------
    always_comb begin
        reg_status = '0;
        reg_status[0] = core_done;
        reg_status[1] = core_busy;
    end

    // ------------------------------------------------------------------
    // AXI-Stream slave -> compute_core
    //   The compute_core always accepts when not waiting on the host to drain
    //   a completed result. We assert TREADY once START has been written and
    //   keep it high through the K_TOTAL beats.
    // ------------------------------------------------------------------
    logic core_in_valid;
    logic [DATA_WIDTH-1:0] pixel_in;
    logic [DATA_WIDTH-1:0] weight_in;
    logic [ACC_WIDTH-1:0]  core_out;
    logic                  core_done_w;

    // Ready when armed (started) and the previous result has been emitted on
    // m_axis (or there is no pending result).
    logic armed_q;          // started, accepting beats
    logic result_pending_q; // a completed result is waiting on m_axis

    assign s_axis_tready = armed_q && !result_pending_q;
    assign core_in_valid = s_axis_tvalid && s_axis_tready;
    assign pixel_in      = s_axis_tdata[7:0];
    assign weight_in     = s_axis_tdata[15:8];

    always_ff @(posedge clk) begin
        if (!aresetn) begin
            armed_q          <= 1'b0;
            result_pending_q <= 1'b0;
            reg_result       <= '0;
            core_busy        <= 1'b0;
            core_done        <= 1'b0;
        end else begin
            // arm on START
            if (start_pulse) begin
                armed_q   <= 1'b1;
                core_busy <= 1'b1;
                core_done <= 1'b0;
            end

            // when compute_core finishes a window, latch result
            if (core_done_w) begin
                reg_result       <= core_out;
                result_pending_q <= 1'b1;
                core_done        <= 1'b1;
                core_busy        <= 1'b0;
                armed_q          <= 1'b0;  // require a new START for next window
            end

            // result handed off to host
            if (m_axis_tvalid && m_axis_tready) begin
                result_pending_q <= 1'b0;
                core_done        <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // AXI-Stream master <- compute_core
    // ------------------------------------------------------------------
    assign m_axis_tdata  = reg_result;
    assign m_axis_tvalid = result_pending_q;
    assign m_axis_tlast  = result_pending_q; // one beat per frame

    // ------------------------------------------------------------------
    // compute_core instance
    // ------------------------------------------------------------------
    compute_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(IN_CHANNELS)
    ) u_core (
        .clk      (clk),
        .rst      (~aresetn),
        .in_valid (core_in_valid),
        .pixel    (pixel_in),
        .weight   (weight_in),
        .out      (core_out),
        .done     (core_done_w)
    );

endmodule

// =============================================================================
// interface_wrapper
//
// Thin alias so that code referencing the module as "interface_wrapper" also
// compiles. All ports are passed through verbatim to interface_axi.
// This exists solely because "interface" is a reserved SV keyword and cannot
// be the top module name; the authoritative implementation is interface_axi.
// =============================================================================
module interface_wrapper #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32
) (
    input  logic                       clk,
    input  logic                       aresetn,
    input  logic [AXI_ADDR_W-1:0]      s_axi_awaddr,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,
    input  logic [AXI_DATA_W-1:0]      s_axi_wdata,
    input  logic [AXI_DATA_W/8-1:0]    s_axi_wstrb,
    input  logic                       s_axi_wvalid,
    output logic                       s_axi_wready,
    output logic [1:0]                 s_axi_bresp,
    output logic                       s_axi_bvalid,
    input  logic                       s_axi_bready,
    input  logic [AXI_ADDR_W-1:0]      s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,
    output logic [AXI_DATA_W-1:0]      s_axi_rdata,
    output logic [1:0]                 s_axi_rresp,
    output logic                       s_axi_rvalid,
    input  logic                       s_axi_rready,
    input  logic [15:0]                s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    output logic [ACC_WIDTH-1:0]       m_axis_tdata,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast
);
    interface_axi #(
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS),
        .AXI_ADDR_W(AXI_ADDR_W), .AXI_DATA_W(AXI_DATA_W)
    ) u (.*);
endmodule
