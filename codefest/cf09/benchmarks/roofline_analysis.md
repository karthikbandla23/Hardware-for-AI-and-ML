# CF09 CLLM — Roofline Analysis
**Project:** INT8 2D Convolution Accelerator (YOLO-style Detection Layer)
**Course:** ECE 410/510 — HW4AI, Spring 2026

---

## Accelerator Point on Roofline

The accelerator throughput used is **projected** (not measured on FPGA). The projected
peak of 3,200 MFLOP/s (3.2 GFLOP/s) at an arithmetic intensity of 45.2 FLOP/byte
(system I/O bound, M1 reference figure) places the accelerator exactly at the
**HW compute ceiling** of the Zynq-7020 roofline. The point is labeled "projected"
on `roofline_plot.png`.

---

## Gap Diagnosis

There is no gap between the projected landing point and where the analysis predicts —
both sit at the 3.2 GFLOP/s compute ceiling. This is expected: the design is
compute-bound at all realistic AI values (45.2 and 278 FLOP/byte both exceed the HW
ridge point of 8.0 FLOP/byte).

However, the projected 1.14× speedup over the measured CPU baseline (2.81 GFLOP/s,
795 inf/s on a Ryzen 7 7730U) is smaller than anticipated. The CPU baseline is stronger
than previously assumed: the Ryzen achieves 2.81 GFLOP/s — close to the accelerator's
3.2 GFLOP/s ceiling — because it benefits from NumPy's optimized INT8 convolution
routines using AVX2 SIMD, effectively issuing multiple MACs per cycle despite scalar
code structure. The **dominant uncertainty** in the projection is whether the line
buffer and window extractor can sustain zero-stall throughput to all 16 MAC units. Any
bubble in the sliding-window pipeline reduces effective MAC utilization below 100% and
proportionally narrows the already-slim speedup margin.

## Converting Projection to Measurement

To convert to a measured result: (1) implement the 16-MAC parallel array with the
line buffer and window extractor in RTL, (2) run a cocotb testbench driving a full
64×64×3 input through the complete pipeline while measuring simulated clock cycles,
then divide total FLOPs by elapsed time. FPGA synthesis and AXI DMA end-to-end timing
would yield the definitive measured point accounting for all interface latency.
