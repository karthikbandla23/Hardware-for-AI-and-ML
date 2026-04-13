# CMAN — Roofline Construction and Kernel Classification

## Hardware Specifications
- **Peak compute:** 10 TFLOPS (FP32) = 10,000 GFLOP/s  
- **Peak DRAM bandwidth:** 320 GB/s  

---

## Task 1: Roofline

### Ridge Point
\[
\text{Ridge Point} = \frac{\text{Peak Compute}}{\text{Peak Bandwidth}} = \frac{10,000}{320} = 31.25 \ \text{FLOP/byte}
\]

- Any kernel with **AI > 31.25 FLOP/byte → Compute-bound**
- Any kernel with **AI < 31.25 FLOP/byte → Memory-bound**

### Roofline Description
- Horizontal line (compute ceiling): **10,000 GFLOP/s**
- Diagonal line (bandwidth limit): slope = **320 GB/s**
- Intersection point: **(31.25 FLOP/byte, 10,000 GFLOP/s)**

- **GEMM kernel:** 170.7 FLOP/byte → on compute ceiling  
- **Vector add:** 0.083 FLOP/byte → on bandwidth ceiling  

---

## Task 2: Kernel A — Dense GEMM (1024 × 1024)

To compute each element of matrix C:
- 1024 multiplications + 1024 additions  
- Total = **2 × 1024 operations per element**  
- Total elements = \(1024 \times 1024\)

### FLOPs
\[
\text{FLOPs} = 2 \times N^3 = 2 \times 1024^3 = 2,147,483,648
\]

### Bytes Transferred (No Cache Reuse)
Each element is FP32 = 4 bytes

- Matrix A: 1024 × 1024 × 4 = 4,194,304 bytes  
- Matrix B: 1024 × 1024 × 4 = 4,194,304 bytes  
- Matrix C: 1024 × 1024 × 4 = 4,194,304 bytes  

**Total = 12,582,912 bytes**

### Arithmetic Intensity
\[
\text{AI} = \frac{2,147,483,648}{12,582,912} = 170.7 \ \text{FLOP/byte}
\]

### Analysis

| Property | Value |
|--------|------|
| AI | 170.7 FLOP/byte |
| Ridge point | 31.25 FLOP/byte |
| Bound | Compute-bound (170.7 >> 31.25) |
| Attainable performance | 10,000 GFLOP/s |

### Recommendation
Kernel A is **compute-bound**, so improvements should target:
- More **FMA units**
- Wider **SIMD/vector units**
- Better **compute throughput**

Increasing memory bandwidth will not significantly improve performance.

---

## Task 3: Kernel B — Vector Addition (Length = 4,194,304)

Each element:
- Load A[i], load B[i], compute A[i] + B[i], store result

### FLOPs
\[
\text{FLOPs} = 4,194,304
\]

### Bytes Transferred (No Cache Reuse)

- Vector A: 4,194,304 × 4 = 16,777,216 bytes  
- Vector B: 4,194,304 × 4 = 16,777,216 bytes  
- Vector C: 4,194,304 × 4 = 16,777,216 bytes  

**Total = 50,331,648 bytes**

### Arithmetic Intensity
\[
\text{AI} = \frac{4,194,304}{50,331,648} = 0.083 \ \text{FLOP/byte}
\]

### Performance
\[
P = \text{AI} \times \text{Bandwidth} = 0.083 \times 320 = 26.7 \ \text{GFLOP/s}
\]

### Analysis

| Property | Value |
|--------|------|
| AI | 0.083 FLOP/byte |
| Ridge point | 31.25 FLOP/byte |
| Bound | Memory-bound (0.083 << 31.25) |
| Attainable performance | 26.7 GFLOP/s |

### Recommendation
Kernel B is **memory-bound**, so improvements should target:
- Higher **memory bandwidth** (e.g., HBM)
- Better **memory access patterns**
- Reducing memory traffic (fusion, streaming)

Adding compute units will not help since they are already underutilized.

---

## Summary

| Kernel | FLOPs | Bytes | AI (FLOP/byte) | Bound | Attainable (GFLOP/s) |
|--------|------|------|---------------|------|----------------------|
| GEMM 1024×1024 | 2,147,483,648 | 12,582,912 | 170.7 | Compute | 10,000 |
| Vector Add (4M) | 4,194,304 | 50,331,648 | 0.083 | Memory | 26.7 |

---

## Final Note
- **Ridge point:** 31.25 FLOP/byte  
- Determines transition between memory-bound and compute-bound regions in the roofline model.
