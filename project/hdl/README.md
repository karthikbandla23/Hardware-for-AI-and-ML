# Project Compute Core — INT8 2D Convolution Accelerator (YOLO Layer)

**Course:** ECE 410/510 — HW4AI, Spring 2026

## Module description

`conv2d_core.v` is the top-level compute module of the INT8 2D convolution accelerator chiplet targeting a single YOLO-style detection layer. The full system (documented in M1) accelerates a 64×64×3 → 64×64×16 convolution with 16 filters of size 3×3×3, using a **weight-stationary dataflow** with **16 parallel INT8 MAC units** and a **3-row line buffer** for input reuse.

This COPT stub implements the inner MAC kernel that will be replicated 16× in the final design. It consumes a stream of (pixel, weight) pairs via a valid/ready handshake, multiplies them element-wise, and accumulates the products into a signed 32-bit register. After `KERNEL_SIZE × KERNEL_SIZE` valid pairs have been MAC'd (27 for a 3×3×3 filter), `done` is asserted and `out` holds the partial sum for one output channel at one spatial position.

Parameters:
- `DATA_WIDTH = 8`   — INT8 pixel and weight width
- `ACC_WIDTH  = 32`  — signed accumulator width
- `KERNEL_SIZE = 3`  — 3×3 spatial kernel (filters are 3×3×3 with 3 input channels)

The implementation applies lessons from CF04 CLLM:
- All arithmetic operands declared `signed`
- `always_ff` for sequential logic
- Synchronous active-high reset
- Explicit sign extension of the 16-bit product to 32 bits before accumulation

A working cocotb testbench (`test_conv2d_core.py`) drives reset and verifies one 3×3 convolution: a Sobel-x filter applied to the pixel patch `[[1,2,3],[4,5,6],[7,8,9]]` yields the expected horizontal-gradient sum of 8. The simulation harness is the foundation for M2's richer verification (sliding-window validation, corner cases, full-layer throughput).

## Interface choice

**AXI4-Stream** for data transfer (input feature maps and output feature maps), paired with **AXI4-Lite** for control registers (layer configuration H/W/C/K/stride/pad, start trigger, done flag).

The accelerator will be instantiated in a Zynq-7020 FPGA SoC. The ARM Cortex-A9 hard processor core serves as the host CPU running pre/post-processing and object detection logic. The conv2d accelerator sits in the programmable logic (PL) fabric and connects to the processing system (PS) via the AXI interconnect.

## Interface justification (M1 arithmetic intensity and bandwidth)

From M1 analysis, the target YOLO conv layer has an **arithmetic intensity of 45.19 FLOP/byte** — deep in the compute-bound region of both CPU and accelerator rooflines (CPU ridge point ~0.67 FLOP/byte). This high intensity comes from massive weight and input reuse:

- **Weight reuse**: 432 bytes of filter weights are loaded once into on-chip registers and reused across all 4,096 output spatial positions — a 4,096× reduction in weight memory traffic vs. naive implementations.
- **Input reuse via line buffer**: The sliding 3×3 window means adjacent output positions share 6 of 9 input values. A 3-row line buffer (576 bytes SRAM) caches active input rows, allowing each pixel to be read from SRAM up to 9 times without external memory access.

At the target inference rate of 14,468 inferences/sec (69 μs/inference from M1 roofline), the required sustained bandwidth is **1.13 GB/s** (per-inference data: 12,288 bytes input + 65,536 bytes output = 77,824 bytes). AXI4-Stream at 32-bit width and 100 MHz provides **0.4 GB/s** — a mismatch, but not a bottleneck: the design is **compute-bound, not interface-bound**. The input loading phase (12 KB at 0.4 GB/s = ~31 μs) is startup latency; once computation begins, new rows stream in while the MAC array processes buffered data. The interface is never starved.

**Why not SPI?** SPI at ~6 MB/s would take ~2 ms to load a 12 KB input, making the interface the bottleneck and destroying the 69 μs target. AXI4-Stream provides the burstable, pipelined data path this streaming kernel actually needs and is the standard fabric IP on Zynq SoCs, making M2 integration straightforward.

## Precision

**INT8 throughout the multiply path, INT32 accumulator.** This matches the symmetric INT8 quantization analyzed in CF04 CMAN (`S = max(|W|)/127`), provides 4× memory savings over FP32 (critical for on-chip weight storage across 16 filters), and keeps each MAC unit small enough to replicate 16× in parallel. The 32-bit accumulator gives ~16 bits of headroom over a single 8×8 product — sufficient for the 27-tap (3×3×3) filters in this layer. CF04 CLLM showed the design wraps cleanly via two's complement when overflow occurs; no saturation logic is required for typical YOLO layer ranges.

## Files

- `conv2d_core.v` — single-MAC compute kernel (will be replicated 16× in M2)
- `test_conv2d_core.py` — cocotb testbench stub
- `Makefile` — `make SIM=icarus` to run

## Run

```bash
cd project/hdl
make SIM=icarus
```

Expected output: `conv result = 8, expected 8, done = 1` → `PASSED`
