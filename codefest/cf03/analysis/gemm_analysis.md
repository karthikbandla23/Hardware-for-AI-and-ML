%%writefile gemm_analysis.md
# GEMM Analysis: Naive vs Tiled (T4 GPU)

## Results Summary
| Kernel | Time (ms) | GFLOP/s | Arithmetic Intensity |
|--------|-----------|---------|----------------------|
| Naive  | 104.205   | 20.61   | 0.250 FLOP/byte      |
| Tiled  | 27.118    | 79.19   | 2.000 FLOP/byte      |

## (a) Why the Naive Kernel is Memory-Bound
The naive kernel assigns one thread per output element C[i][j]. Each thread independently
loads a full row of A and a full column of B directly from global DRAM, with no data reuse
across threads. For a 1024x1024 matrix, this means 2N^3 = 2.15 billion element accesses
with no caching, yielding an arithmetic intensity of only 0.25 FLOP/byte — far below the
T4 ridge point of 27 FLOP/byte. The kernel spends the vast majority of its time waiting
for memory transfers rather than performing compute, making it deeply memory-bound.

## (b) How Tiling Reduces DRAM Traffic
The tiled kernel loads T×T submatrices (tiles) of A and B into shared memory once, then
reuses them for all T dot-product contributions within that tile before fetching the next
tile from DRAM. Each element is loaded from global memory only N/T times instead of N
times, reducing total DRAM traffic by a factor of T=8. This raises the arithmetic intensity
from 0.25 to 2.0 FLOP/byte — an 8x improvement — because the same data now serves
T multiply-accumulate operations from fast on-chip shared memory instead of slow DRAM.

## (c) Whether the Tiled Kernel Achieved the Expected Improvement
The tiled kernel achieved 79.19 GFLOP/s vs 20.61 GFLOP/s for naive — a 3.84x speedup.
The expected improvement from 8x traffic reduction would suggest ~8x speedup, but the
actual gain is ~4x. The remaining bottleneck is that TILE=8 is too small to fully hide
memory latency or saturate the T4's warp scheduler — with only 64 threads per block,
occupancy is low and the GPU cannot overlap enough memory transactions with computation.
Both kernels remain memory-bound (AI=2.0 < ridge point of 27 FLOP/byte), meaning a
larger tile size (e.g., TILE=32) would be needed to approach compute-bound territory
and fully exploit the T4's 8.1 TFLOP/s peak compute throughput.
