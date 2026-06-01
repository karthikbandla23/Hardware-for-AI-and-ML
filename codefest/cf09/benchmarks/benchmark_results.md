# CF09 CLLM — Benchmark Results
**Project:** INT8 2D Convolution Accelerator (YOLO-style Detection Layer)
**Course:** ECE 410/510 — HW4AI, Spring 2026

---

## Workload

**Kernel:** 2D convolution — 64×64×3 input, 16 filters of 3×3×3, stride 1, pad 1 → 64×64×16 output
**FLOPs per inference:** 3,538,944 (1,769,472 MACs × 2)
**Data:** 12,288 B input + 432 B weights + 65,536 B output = 78,256 B per inference

---

## Results Table

| Metric | SW Baseline (CPU, M1 measured) | HW — Current RTL (simulation) | HW — Projected 16-MAC (M3/M4 target) |
|---|---|---|---|
| **Platform** | AMD Ryzen 7 7730U, Python 3.13, NumPy | `compute_core.sv` + `interface.sv`, 1 MAC unit, cocotb/Icarus | Same RTL ×16, weight-stationary dataflow |
| **Clock / frequency** | 4.5 GHz boost (scalar execution) | 100 MHz (simulated) | 100 MHz (projected) |
| **Execution time / inference** | **1,257 μs** (median, N=1000) | 17,690 μs (projected) | **1,106 μs** (projected) |
| **Throughput** | **2,814.72 MFLOP/s (2.81 GFLOP/s)** | 200 MFLOP/s (projected) | **3,200 MFLOP/s (3.2 GFLOP/s)** (projected) |
| **Inferences / sec** | **795** | 57 (projected) | **904** (projected) |
| **% of platform peak** | 3.91% of CPU peak (72 GFLOP/s) | 100% MAC utilization (1/1) | 100% MAC utilization (16/16, projected) |
| **Peak memory (RSS)** | **1,215.79 KB** | N/A (simulation) | N/A |
| **Speedup vs SW baseline** | 1.00× (reference) | **0.07×** (expected — single MAC stub) | **1.14×** (projected) |
| **Energy** | Not measured | Not available (simulation only) | Not available |

> **Labeling:** All HW rows are **projected** — derived from `clock_frequency × useful_operations_per_cycle` using verified RTL simulation. No end-to-end FPGA measurement has been performed. The current RTL is a single-MAC stub; the 16-MAC parallel array is the M3/M4 integration target.

---

## Projection Assumptions (Task 7)

### Current RTL (1 MAC unit)
- Simulation confirms **1 MAC/cycle** throughput at 100 MHz — verified from `tb_compute_core`: T1 completes 27 MACs in exactly 27 clock cycles (`$finish` at 606 ns for 2 test windows including reset overhead).
- Peak throughput: `1 MAC/cycle × 100 MHz × 2 FLOPs/MAC = 200 MFLOP/s`
- Per-inference time: `1,769,472 MACs ÷ 100×10⁶ MACs/s = 17.69 ms`
- No pipeline stalls assumed — AXI4-Stream backpressure (TREADY deasserted between windows) adds overhead not captured here.

### Projected 16-MAC array
- 16 instances of `compute_core` run in parallel, one per output filter.
- All 16 MACs active every cycle (weight-stationary, weights pre-loaded in registers).
- Peak throughput: `16 × 100 MHz × 2 FLOPs/MAC = 3,200 MFLOP/s = 3.2 GFLOP/s`
- Per-inference: `1,769,472 MACs ÷ (16 × 100×10⁶) = 1,106 μs`
- Interface not a bottleneck: input load at 0.4 GB/s takes ~31 μs startup; compute dominates at 1,106 μs.
- **Key assumption:** line buffer and window extractor (not yet implemented) supply 27 pixel/weight pairs per cycle without stalls. This is the dominant uncertainty — see `roofline_analysis.md`.

---

## Speedup Computation

```
Speedup (projected 16-MAC vs SW baseline) = 904 inf/s ÷ 795 inf/s = 1.14×

Throughput ratio = 3,200 MFLOP/s ÷ 2,814.72 MFLOP/s = 1.14×
```

The speedup is modest (1.14×) because the CPU baseline is itself strong — the Ryzen 7 7730U achieves 2.81 GFLOP/s despite using only 3.91% of its 72 GFLOP/s peak. Both platforms are compute-bound above their respective ridge points. The accelerator's 16 INT8 MACs at 100 MHz (3.2 GFLOP/s peak) barely exceeds the CPU's measured scalar throughput. A larger MAC array (32+ units) or higher clock (150–200 MHz after timing optimization) would widen this gap. Doubling MAC count to 32 yields a projected 2.27× speedup.

---

## SW Baseline Reference (M1 — measured)

| Parameter | Value |
|---|---|
| CPU | AMD Ryzen 7 7730U (AVX2, 4.5 GHz boost, 8 cores) |
| OS | Windows 11 |
| Python / NumPy | 3.13.0 / 2.4.4 |
| Median exec time | 1,257.30 μs (N=1000) |
| Mean exec time | 1,261.60 μs |
| Std dev | 44.98 μs |
| Throughput | 2,814.72 MFLOP/s |
| Inferences/sec | 795 |
| % of CPU peak | 3.91% |
| Peak RSS | 1,215.79 KB |
| Conv2D % of pipeline | ~99.2% |
