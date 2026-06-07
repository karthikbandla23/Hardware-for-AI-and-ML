// =============================================================================
// top.sv
//
// Top-level integration shell for the full INT8 Conv2D Accelerator.
// Project: ECE 410/510 HW4AI Spring 2026 — Milestone 4.
//
// This module instantiates interface_axi which contains the full accelerator:
//   - line_buffer    : 3-row x 64-col x 3-ch sliding window buffer
//   - weight_regs    : 16 x 27 x INT8 weight register file
//   - mac_array      : 16 parallel compute_core MAC units
//   - output_pipeline: bias + ReLU + INT32->INT8 requantization
//   - control_fsm    : nested loop control for full 64x64 layer
//   - interface_axi  : AXI4-Lite control + AXI4-Stream data
//
// Changes from M3:
//   - AXI4-Stream slave TDATA is now 8-bit (pixel only, not pixel+weight)
//   - AXI4-Stream master TDATA is now 128-bit (16 x INT8 packed results)
//   - AXI4-Lite register map extended for weight/bias loading
//   - Full layer (64x64x3 -> 64x64x16) implemented, not just single MAC
// =============================================================================

`timescale 1ns / 1ps

module top #(
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

    // ---- AXI4-Stream slave (input pixels, 8-bit) ----
    input  logic [DATA_WIDTH-1:0]        s_axis_tdata,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,

    // ---- AXI4-Stream master (output: 16 x INT8 packed = 128-bit) ----
    output logic [NUM_FILTERS*DATA_WIDTH-1:0] m_axis_tdata,
    output logic                              m_axis_tvalid,
    input  logic                              m_axis_tready,
    output logic                              m_axis_tlast
);

    interface_axi #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(IN_CHANNELS),
        .NUM_FILTERS(NUM_FILTERS),
        .IMG_W      (IMG_W),
        .AXI_ADDR_W (AXI_ADDR_W),
        .AXI_DATA_W (AXI_DATA_W)
    ) u_interface (
        .clk            (clk),
        .aresetn        (aresetn),
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
