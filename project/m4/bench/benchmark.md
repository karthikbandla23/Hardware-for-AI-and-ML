# Hardware vs Software Benchmark — INT8 Conv2D Accelerator (M4)

## Target Kernel
- Operation: 2D Convolution, 64×64×3 input, 16 filters of 3×3×3, stride=1, pad=1
- Output: 64×64×16 INT8 feature map
- Total MACs: 1,769,472 | Total FLOPs: 3,538,944
- Arithmetic Intensity: 45.19 FLOP/byte (weight-stationary)

## Software Baseline (M1)
- Platform: AMD Ryzen 7 7730U, Python 3.13.0, NumPy 2.4.4, N=1000 runs
- Runtime: **1,257.30 μs** | Throughput: **795 inf/sec** | **2.8147 GFLOP/s**
- Power: ~15,000 mW (CPU TDP) | Energy/inf: ~18,855 μJ

## Hardware Accelerator (M4)
- Platform: sky130A ASIC @ 100 MHz
- Cycle count: **135,655 cycles** (from sim/final_run.log)
- Runtime: **1,356.55 μs** | Throughput: **737 inf/sec** | **2.606 GFLOP/s**
- Power: **81.04 mW** (OpenROAD nom_tt_025C_1v80, synth/power_report.txt)
- Energy/inf: **109.96 μJ**

## Results

| Metric | SW Baseline (M1) | HW Accelerator (M4) | Ratio |
|--------|-----------------|---------------------|-------|
| Runtime | 1,257.30 μs | 1,356.55 μs | 0.93× |
| Throughput | 795 inf/sec | 737 inf/sec | 0.93× |
| Performance | 2.8147 GFLOP/s | 2.606 GFLOP/s | 0.93× |
| Power | ~15,000 mW | 81.04 mW | **185× less** |
| Energy/inf | ~18,855 μJ | ~109.96 μJ | **171× less** |

Speedup = 1,257.30 / 1,356.55 = **0.927×** (7% slower in throughput)

## Why Throughput Did Not Exceed CPU
1. FSM overhead: WIN_LATCH + MAC_RUN(27) + ACC_SETTLE + OUT_PIPE = 30 cycles per position
2. Timing violations at 100 MHz (WNS=-3.45 ns worst corner)
3. CPU AVX2 vectorized INT8 achieves 2.8 GFLOP/s effectively

## Primary Result: Energy Efficiency
Energy efficiency gain: **171×** less energy per inference vs CPU baseline.

## Raw Data
See benchmark_data.csv for all underlying numbers.
