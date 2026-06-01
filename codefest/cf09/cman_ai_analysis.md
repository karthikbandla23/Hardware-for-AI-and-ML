# CF09 CMAN — Arithmetic Intensity Analysis
**Project:** INT8 2D Convolution Accelerator (YOLO-style Detection Layer)
**Course:** ECE 410/510 — HW4AI, Spring 2026

---

## Task 1 — Dominant Kernel

**Kernel:** Standard 2D convolution (weight-stationary dataflow)

| Parameter | Value |
|---|---|
| Input feature map | 64 × 64 × 3 (INT8) |
| Filters | 16 × 3×3×3 (INT8) |
| Output feature map | 64 × 64 × 16 (INT8) |
| Stride / padding | 1 / 1 (same) |
| MACs per output pixel | 3 × 3 × 3 = **27** |
| Data type — multiply | INT8 × INT8 → INT16 |
| Data type — accumulate | INT32 |

---

## Task 2 — FLOPs Count

Each MAC counts as 2 FLOPs (1 multiply + 1 add).

```
Output pixels  = 64 × 64 × 16        = 65,536
MACs per pixel = 3 × 3 × 3           = 27
Total MACs     = 65,536 × 27         = 1,769,472
Total FLOPs    = 1,769,472 × 2       = 3,538,944 FLOPs  (~3.54 MFLOPs)
```

---

## Task 3 — Bytes Transferred (Two Bounds)

### Data sizes

| Data | Formula | Bytes |
|---|---|---|
| Input feature map | 64 × 64 × 3 × 1 B | **12,288 B** |
| Filter weights | 16 × 3 × 3 × 3 × 1 B | **432 B** |
| Output feature map | 64 × 64 × 16 × 1 B | **65,536 B** |

### Lower bound — no data reuse

Every weight and every input pixel is re-fetched from off-chip memory for every output pixel it contributes to. No caching assumed.

```
Each output pixel reads:
  - 27 input bytes  (fresh from DRAM)
  - 27 weight bytes (fresh from DRAM)

Bytes_no_reuse = 65,536 × (27 + 27)
               = 65,536 × 54
               = 3,538,944 bytes

AI_lower = 3,538,944 FLOPs / 3,538,944 bytes = 1.0 FLOP/byte
```

### Upper bound — perfect weight-stationary reuse

Weights (432 B) are loaded once into on-chip registers and reused across all 4,096 spatial positions. Input activations are streamed once through the 3-row line buffer (each pixel read at most once from off-chip). Output is written once. This matches the actual design dataflow.

```
Bytes_weight_stationary = 12,288 (input, streamed once)
                        + 432   (weights, loaded once)
                        = 12,720 bytes

AI_upper = 3,538,944 / 12,720 = 278.2 FLOP/byte
```

### System-level I/O bound (M1 reference figure)

Treats the accelerator as a black box: both input and output traffic go to/from DRAM.

```
Bytes_system = 12,288 (input) + 432 (weights) + 65,536 (output)
             = 78,256 bytes

AI_system = 3,538,944 / 78,256 = 45.2 FLOP/byte
```

> **Note:** The 45.19 FLOP/byte figure from M1 corresponds to this system-level I/O calculation. It is the most conservative realistic estimate (lower than weight-stationary, higher than no-reuse). Both the system-level and weight-stationary values are valid depending on whether output DRAM write-back is included in the denominator.

---

## Task 4 — Arithmetic Intensity Summary

| Bound | Bytes transferred | AI (FLOP/byte) | Region |
|---|---|---|---|
| No reuse (lower) | 3,538,944 B | **1.0** | Memory-bound |
| System I/O (M1 figure) | 78,256 B | **45.2** | Compute-bound |
| Weight-stationary + line buffer (upper) | 12,720 B | **278.2** | Compute-bound |

### Target Platform: Zynq-7020 FPGA

| Platform parameter | Value |
|---|---|
| MAC units | 16 parallel INT8 MACs |
| Clock frequency | 100 MHz |
| Peak compute | 16 × 2 × 100×10⁶ = **3.2 GFLOP/s** |
| AXI4-Stream BW (32-bit @ 100 MHz) | **0.4 GB/s** |
| Ridge point | 3.2 / 0.4 = **8.0 FLOP/byte** |

### Roofline Position

Both the system-level AI (45.2 FLOP/byte) and the weight-stationary AI (278.2 FLOP/byte) are **well above the ridge point of 8.0 FLOP/byte**. The design is firmly **compute-bound** at all realistic operating points.

The no-reuse lower bound (1.0 FLOP/byte) falls in the memory-bound region, but is only a theoretical worst case that the weight-stationary dataflow explicitly avoids.

**Attainable performance range:**
```
P_lower  = min(3.2 GFLOP/s,  1.0  × 0.4 GB/s) = 0.40 GFLOP/s  (memory-bound, no reuse)
P_system = min(3.2 GFLOP/s, 45.2  × 0.4 GB/s) = 3.2  GFLOP/s  (compute ceiling)
P_upper  = min(3.2 GFLOP/s, 278.2 × 0.4 GB/s) = 3.2  GFLOP/s  (compute ceiling)
```

The design operates at the **compute ceiling (3.2 GFLOP/s)** for both realistic AI bounds.

### CPU Baseline Roofline (M1 comparison)

| CPU parameter | Value |
|---|---|
| Measured CPU throughput | 1.29 GFLOP/s |
| CPU peak (estimated) | ~19.9 GFLOP/s |
| CPU memory BW | ~30 GB/s (DDR3) |
| CPU ridge point | ~0.67 FLOP/byte |

At AI = 45.2 FLOP/byte, the CPU is also compute-bound (above its ridge point of 0.67). Despite being compute-bound, measured CPU throughput is only 1.29 GFLOP/s (~6.5% of peak) due to scalar execution and lack of SIMD utilization.

---

## Task 5 — Bottleneck & Improvement

### Current bottleneck

**Compute.** Both AI bounds (45.2 and 278.2 FLOP/byte) are above the accelerator ridge point of 8.0 FLOP/byte. The AXI4-Stream interface at 0.4 GB/s is not the throughput bottleneck — it imposes a ~31 μs input loading latency (12,288 B ÷ 0.4 GB/s), which is startup overhead rather than a sustained throughput limit. Once the line buffer is primed, new rows stream in while the MAC array processes buffered data.

The design is **not interface-bound, not memory-bound**. It is **compute-bound at the 3.2 GFLOP/s ceiling**.

### Single highest-leverage improvement

**Double the MAC array from 16 to 32 units.** This doubles peak throughput to 6.4 GFLOP/s with no interface changes. The ridge point shifts to 6.4/0.4 = 16.0 FLOP/byte, still well below both realistic AI bounds (45.2 and 278.2), so the design remains compute-bound and the full 2× speedup is realized. Widening the AXI4-Stream bus (e.g., to 64-bit for 0.8 GB/s) would not help throughput because the bottleneck is compute, not interface bandwidth.

---

*Roofline sketch: see `cman_roofline_sketch.png` in the same directory.*
