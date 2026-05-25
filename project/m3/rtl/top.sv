// =============================================================================
// top.sv
//
// Integrated top-level module for the INT8 2D Convolution Accelerator.
// Project: ECE 410/510 HW4AI Spring 2026 — Milestone 3.
//
// This module is a thin integration shell. It instantiates:
//   1. interface_axi   — AXI4-Lite (control) + AXI4-Stream (data) wrapper
//      from project/m2/rtl/interface.sv.  The interface already contains an
//      embedded compute_core instance; top.sv exposes the full AXI port list
//      to the outside world (FPGA SoC / testbench).
//
// Design note — no additional glue logic is required:
//   The M2 interface_axi module already instantiates compute_core internally
//   and connects all inter-module signals (core_in_valid, pixel_in,
//   weight_in, core_out, core_done_w, armed_q, result_pending_q).  There are
//   no clock-domain crossings (single clk domain throughout), no FIFO
//   adapters, and no width converters needed at this integration level.
//   top.sv therefore contains only port declarations and the single DUT
//   instantiation — all functional logic lives in the sub-modules.
//
// External ports (host-facing)
// ----------------------------
// clk            in   1      System clock (100 MHz nominal).
// aresetn        in   1      AXI-style synchronous active-low reset.
//
// AXI4-Lite slave (control plane — ARM Cortex-A9 register accesses)
// s_axi_awaddr   in   32     Write address.
// s_axi_awvalid  in   1      Write address valid.
// s_axi_awready  out  1      Write address ready.
// s_axi_wdata    in   32     Write data.
// s_axi_wstrb    in   4      Write byte strobes.
// s_axi_wvalid   in   1      Write data valid.
// s_axi_wready   out  1      Write data ready.
// s_axi_bresp    out  2      Write response (OKAY/SLVERR).
// s_axi_bvalid   out  1      Write response valid.
// s_axi_bready   in   1      Write response ready.
// s_axi_araddr   in   32     Read address.
// s_axi_arvalid  in   1      Read address valid.
// s_axi_arready  out  1      Read address ready.
// s_axi_rdata    out  32     Read data.
// s_axi_rresp    out  2      Read response.
// s_axi_rvalid   out  1      Read data valid.
// s_axi_rready   in   1      Read data ready.
//
// AXI4-Stream slave (input data — pixel/weight pairs from DMA)
// s_axis_tdata   in   16     [15:8]=weight INT8, [7:0]=pixel INT8.
// s_axis_tvalid  in   1      Input beat valid.
// s_axis_tready  out  1      Input beat ready (backpressure).
// s_axis_tlast   in   1      End-of-frame marker (accepted, framing by counter).
//
// AXI4-Stream master (output result — INT32 accumulator to DMA)
// m_axis_tdata   out  32     Signed INT32 convolution result.
// m_axis_tvalid  out  1      Output beat valid.
// m_axis_tready  in   1      Output beat ready.
// m_axis_tlast   out  1      Asserted with every output beat (1 result/frame).
// =============================================================================

`timescale 1ns / 1ps

module top #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACC_WIDTH   = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int IN_CHANNELS = 3,
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32
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

    // ---- AXI4-Stream slave (input) ----
    input  logic [15:0]                 s_axis_tdata,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic                        s_axis_tlast,

    // ---- AXI4-Stream master (output) ----
    output logic [ACC_WIDTH-1:0]        m_axis_tdata,
    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic                        m_axis_tlast
);

    // ------------------------------------------------------------------
    // interface_axi instantiation
    //
    // interface_axi (from m2/rtl/interface.sv) contains an embedded
    // compute_core instance connected through internal signals.
    // No glue logic is required between this shell and the sub-module:
    //   - Single clock domain: clk drives both AXI FSMs and compute_core.
    //   - Reset polarity: aresetn (active-low) passed directly; interface_axi
    //     generates the active-high rst = ~aresetn for compute_core internally.
    //   - Data widths match exactly (DATA_WIDTH=8, ACC_WIDTH=32, KERNEL_SIZE=3,
    //     IN_CHANNELS=3) — no adapters needed.
    // ------------------------------------------------------------------
    interface_axi #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE),
        .IN_CHANNELS (IN_CHANNELS),
        .AXI_ADDR_W  (AXI_ADDR_W),
        .AXI_DATA_W  (AXI_DATA_W)
    ) u_interface (
        .clk            (clk),
        .aresetn        (aresetn),
        // AXI4-Lite
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        // AXI4-Stream
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

endmodule
