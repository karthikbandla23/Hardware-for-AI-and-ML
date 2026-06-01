# Remaining Tasks Before M4
**Project:** INT8 2D Convolution Accelerator (YOLO-style Detection Layer)
**Course:** ECE 410/510 — HW4AI, Spring 2026

---

## Task 1 — Implement the 3-row line buffer and 3×3×3 window extractor in RTL

The current `compute_core.sv` accepts a flat stream of (pixel, weight) pairs but has no
spatial awareness. Before M4, implement a `line_buffer.sv` module that stores 3 rows of
the 64×3-channel input (576 bytes of SRAM), generates overlapping 3×3 windows as the
column index advances, and outputs 27 (pixel, weight) pairs per cycle to the MAC array.
The window extractor must handle zero-padding at the borders (same padding, stride 1)
and assert a `window_valid` strobe exactly once per output spatial position. Without
this, the 16-MAC array cannot be fed at full utilization and the 3.2 GFLOP/s projection
cannot be validated.

## Task 2 — Instantiate 16 parallel `compute_core` units and add a bias + ReLU output pipeline

The current `interface.sv` connects to a single `compute_core` instance. For M4,
replicate the core 16 times (one per output filter), fan out the shared pixel stream to
all 16 cores, route each core's dedicated weight stream from the weight register file
(16 × 432 B = 6,912 B total), and collect the 16 INT32 partial sums into a bias-add and
ReLU → requantize pipeline that produces 16 INT8 output values per clock cycle. The
weight register file must be loadable via AXI4-Lite before inference begins, with the
KERNEL_CFG register extended to track load progress.

## Task 3 — Replace the 27-cycle sequential accumulation in `compute_core` with a 5-stage pipelined accumulator tree to reduce critical-path delay

The current `compute_core` uses a flat `out <= out + product_ext` chain that adds one
product per cycle over 27 cycles. Synthesis on the Zynq-7020 will place the 32-bit
adder on the critical path at approximately 2.4 ns, limiting the maximum clock frequency
below 100 MHz when the 16-instance array is instantiated. Replacing the sequential
accumulation with a depth-4 adder tree (27 products → 14 → 7 → 4 → 2 → 1, pipelined
across 5 stages) reduces the critical-path adder depth to a single level per stage,
allowing the design to meet 100 MHz timing closure and enabling a higher clock target
(150–200 MHz) in the final M4 synthesis run.
