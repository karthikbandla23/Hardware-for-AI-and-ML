# HW/SW Partition Rationale - INT8 2D Convolution Accelerator

## (a) Which kernel(s) to accelerate in hardware and why the roofline analysis supports that choice

The **2D convolution** operation is selected for hardware acceleration. Profiling of a
simplified YOLO detection pipeline (conv2D -> ReLU -> max pool) shows that convolution
accounts for **99.2%** of total pipeline runtime, performing 1,769,472
multiply-accumulate operations per inference.

The arithmetic intensity of the target convolution layer is **45.19 FLOP/byte**. On
the AMD Ryzen 7 7730U with peak bandwidth of 51.2 GB/s, the ridge point is
1.4 FLOP/byte. Since 45.19 >> 1.4, the kernel is
**compute-bound** on the CPU. The CPU achieves only 2.8147 GFLOP/s, which is
3.91% of peak, limited by single-threaded scalar execution
of the nested-loop convolution rather than by memory bandwidth. A dedicated hardware
accelerator with 16 parallel INT8 MAC units running at 100 MHz provides
3.2 GFLOP/s peak throughput, representing a potential
1x speedup from parallelism alone.

## (b) What the software baseline will continue to handle

The host processor retains responsibility for: pre-processing (image scaling, color space
conversion, normalization to INT8), post-conv operations (ReLU, batch normalization, max
pooling -- these are element-wise operations with negligible runtime at <1%
of pipeline), detection head (bounding box decoding, non-maximum suppression, confidence
thresholding -- irregular control flow unsuited to fixed-function hardware), and multi-layer
sequencing if extending to multiple conv layers.

## (c) Interface bandwidth required to avoid becoming interface-bound

At the HW accelerator's target throughput of ~14,468 inferences/sec:
Input bandwidth: 14,468 x 12,288 B = **0.1778 GB/s**.
Output bandwidth: 14,468 x 65,536 B = **0.9481 GB/s**.
Total required: **1.1259 GB/s**.
AXI4-Stream at 32-bit width and 100 MHz provides **0.4 GB/s**,
which exceeds the requirement. The design is **not interface-bound**.

## (d) Whether the kernel is compute-bound or memory-bound, and whether the HW design changes that

The conv2D kernel is **compute-bound** on the current CPU hardware (AI of 45.19 FLOP/byte
is 32x above the CPU ridge point of 1.4 FLOP/byte). The
CPU underperforms not because of memory bandwidth limitations but because it processes only
one MAC per cycle in scalar mode. The hardware accelerator maintains the compute-bound
classification (HW ridge point = 0.25 FLOP/byte, still well below the kernel AI),
but raises the compute ceiling by 16x through parallel MAC units, converting the
unused parallelism in the algorithm into actual throughput.
