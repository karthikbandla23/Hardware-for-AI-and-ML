# Software Baseline Benchmark - INT8 2D Convolution (YOLO Layer)

## Platform and Configuration

| Parameter       | Value                          |
|-----------------|--------------------------------|
| CPU             | AMD Ryzen 7 7730U                     |
| CPU Specs       | AVX2, 4.5 GHz boost, 8 cores  |
| Peak FP32       | 72.0 GFLOP/s (single core, source: AMD product page) |
| Peak DRAM BW    | 51.2 GB/s (DDR4-3200 dual channel, source: AMD product page) |
| OS              | Windows-11-10.0.26200-SP0          |
| Python          | 3.13.0    |
| NumPy           | 2.4.4               |
| Data type       | INT8 inputs/weights, INT32 accumulation |
| Input shape     | 64x64x3          |
| Filter shape    | 16x3x3x3        |
| Output shape    | 64x64x16        |
| Stride / Pad    | 1 / 1               |
| Batch size      | 1 (single image inference)     |

## Layer Statistics

| Metric                        | Value              |
|-------------------------------|-------------------|
| Total MACs                    | 1,769,472    |
| Total FLOPs                   | 3,538,944   |
| Input size                    | 12,288 bytes (12.0 KB) |
| Weight size                   | 432 bytes  |
| Output size                   | 65,536 bytes (64.0 KB) |
| Arithmetic intensity          | 45.19 FLOP/byte |

## Execution Time

| Metric                  | Value              |
|-------------------------|--------------------|
| Median (N=1000)   | 1257.30 us |
| Mean                    | 1261.60 us   |
| Std dev                 | 44.98 us    |
| Min                     | 1194.60 us    |
| 99th percentile         | 1421.93 us    |

## Throughput

| Metric                | Value                              |
|-----------------------|------------------------------------|
| Inferences/sec        | 795                 |
| MFLOP/s               | 2814.72                       |
| GFLOP/s               | 2.8147                       |
| % of CPU peak         | 3.91%     |

## Memory Usage

| Metric              | Value              |
|---------------------|--------------------|
| Peak RSS            | 1215.79 KB |
| Input tensor        | 12,288 bytes |
| Weight tensor       | 496 bytes |
| Output tensor       | 65,536 bytes |

## Pipeline Context

When Conv2D is measured within a simplified YOLO detection pipeline
(conv -> ReLU -> max pool):

| Component           | Time                |
|---------------------|---------------------|
| Full pipeline       | 1257.30 us |
| Conv2D portion      | ~99.2% of pipeline |

Conv2D is the dominant bottleneck and the target for hardware acceleration.
