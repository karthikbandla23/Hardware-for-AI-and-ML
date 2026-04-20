# CMAN 3 — DRAM Traffic Analysis (Naive vs Tiled)

## 1. Naive Matrix Multiplication

Total accesses:

- A accesses = N³ = 32³ = 32,768  
- B accesses = N³ = 32,768  
- Writes (C) = N² = 1,024  

### DRAM Traffic

- A: 32,768 × 4 = 131,072 bytes  
- B: 32,768 × 4 = 131,072 bytes  
- C: 1,024 × 4 = 4,096 bytes  

**Total:**

T_naive = 131,072 + 131,072 + 4,096 = 266,240 bytes


---

## 2. Tiled Matrix Multiplication (T = 8)

Number of tiles:

(N / T)² = (32 / 8)² = 16 tiles


Each tile:

T × T = 8 × 8 = 64 elements
Bytes per tile = 64 × 4 = 256 bytes


### DRAM Traffic

- A: 64 tiles × 256 = 16,384 bytes  
- B: 64 tiles × 256 = 16,384 bytes  
- C writes: 1,024 × 4 = 4,096 bytes  

**Total:**

T_tiled = 16,384 + 16,384 + 4,096 = 36,864 bytes


---

## 3. Traffic Reduction Ratio


Ratio = T_naive / T_tiled
= 266,240 / 36,864
≈ 7.22 ≈ 8


**Conclusion:**

- Tiling reduces DRAM traffic by approximately **T = 8**
- Reason: each element is reused within tiles instead of reloaded

---

## 4. Performance Analysis

### Total FLOPs


Work = 2N³ = 2 × 32³ = 65,536 FLOPs


### Ridge Point


I_ridge = Compute / Bandwidth
= 10 TFLOPS / 320 GB/s
= 31.25 FLOPs/byte


### Compute Time


T_compute = 65,536 / (10 × 10¹²)
= 6.55 × 10⁻⁹ sec


---

## Memory Time

### Naive


T_mem_naive = 266,240 / (320 × 10⁹)
= 8.32 × 10⁻⁷ sec


### Tiled


T_mem_tiled = 36,864 / (320 × 10⁹)
= 1.15 × 10⁻⁷ sec


---

## Final Conclusion

- Naive: Memory time ≫ Compute time → **Memory Bound**
- Tiled: Memory time still > Compute time → **Memory Bound**

Even after tiling, performance is limited by memory bandwidth.
