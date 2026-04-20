
Given
Matrix size: N = 32
Tile size: T = 8
FP32 = 4 bytes
DRAM Bandwidth = 320 GB/s
Compute = 10 TFLOPS
1. Naive Matrix Multiply (ijk)

For each output element:

Read N elements from A
Read N elements from B

Total accesses:

A = N³ = 32³ = 32,768
B = N³ = 32³ = 32,768
Total = 2N³ = 65,536

Add C writes:

C = N² = 1,024
Total DRAM Traffic
T
naive
	​

=(2N
3
+N
2
)×4
=(65,536+1,024)×4=266,240 bytes ≈260 KB
2. Tiled Matrix Multiply (T = 8)
(a) Traditional Tiling
Each element reused T = 8 times
Each element loaded N/T = 4 times
T
tiled
	​

=(2N
3
/T+N
2
)×4
=(8,192+1,024)×4=36,864 bytes ≈36 KB
(b) Ideal Reuse (Perfect Cache/Shared Memory)

Each element loaded only once:

T
ideal
	​

=3N
2
×4
=3×1,024×4=12,288 bytes =12 KB
3. Traffic Reduction
Naive → Tiled:
≈T=8× reduction
Naive → Ideal:
≈N=32× reduction (dominant term)
4. Arithmetic Intensity & Performance
Ridge Point
I
rp
	​

=
320 GB/s
10 TFLOPS
	​

=31.25 FLOPs/byte
Work
FLOPs=2N
3
=65,536
Compute Time
T
comp
	​

=
10
13
65,536
	​

=6.55 ns
5. Comparison Table
Metric	Naive	Tiled	Ideal
Bytes	266,240	36,864	12,288
Arithmetic Intensity	0.246	1.78	5.33
Memory Time	831.4 ns	115.2 ns	38.4 ns
Compute Time	6.55 ns	6.55 ns	6.55 ns
Total Time	837.95 ns	121.75 ns	44.95 ns
Final Insight (Very Important)
All cases are memory-bound
Because:
Arithmetic Intensity≪31.25

Even with perfect reuse:

Compute is underutilized
Performance is limited by memory bandwidth
One-Line Summary

Tiling reduces DRAM traffic significantly (8× to 32×), but for small matrices like N = 32, the computation is still memory-bound, not compute-bound.
