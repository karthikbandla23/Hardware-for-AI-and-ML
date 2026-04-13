# Heilmeier Questions — INT8 2D Convolution Accelerator (YOLO-style Detection Layer)

## Q1: What are you trying to do?

Design and implement a fixed-function INT8 2D convolution accelerator co-processor chiplet
that accelerates a single convolutional layer from a YOLO-style object detection network.
The target layer takes a 64×64×3 INT8 input feature map and applies 16 filters of size
3×3×3 with stride 1 and padding 1 to produce a 64×64×16 INT8 output feature map. The
accelerator uses a weight-stationary dataflow with a parallel MAC array and on-chip line
buffer, connected to an FPGA SoC host via AXI4-Stream (data) and AXI4-Lite (control).
The goal is to achieve significant speedup over a CPU software baseline by exploiting the
massive data reuse and parallelism inherent in 2D convolution.

## Q2: What is done today and what are the limits?

Today, convolutional layers in object detection models like YOLO are executed on
general-purpose CPUs or GPUs. Profiling a simplified YOLO detection pipeline
(conv2D → ReLU → max pool) on a CPU shows that the **2D convolution accounts for 99.5%
of total pipeline runtime**, performing 1,769,472 multiply-accumulate operations per
inference. The software baseline achieves 1,295 MFLOP/s (1.29 GFLOP/s), which is only
~6.5% of the CPU's peak compute capability.

The arithmetic intensity of this convolution layer is **45.19 FLOP/byte**, placing it deep
in the compute-bound region of the CPU roofline (ridge point ~0.67 FLOP/byte). Despite
being compute-bound, the CPU underperforms because it processes one MAC per cycle per
core using scalar execution. The theoretical parallelism in convolution (every output
pixel is independent) is almost entirely unexploited by the sequential CPU pipeline.

On GPUs, convolution runs faster through parallelism, but requires the full GPU power
budget, memory subsystem, and software stack (CUDA, cuDNN). For edge deployment in
resource-constrained environments (embedded systems, IoT devices, robotics), a dedicated
low-power accelerator that exploits the fixed structure of convolution can provide the
necessary throughput at a fraction of the power and silicon area.

## Q3: What is your approach and why is it better?

The approach is a weight-stationary 2D convolution accelerator with 16 parallel INT8 MAC
units and an on-chip line buffer. The architecture exploits two key properties of
convolution:

1. **Weight reuse**: The 432 bytes of filter weights are loaded once into registers and
   reused across all 4,096 output spatial positions. With a weight-stationary dataflow,
   each weight is read once from memory and used 4,096 times — a 4,096× reduction in
   weight memory traffic compared to a naive implementation.

2. **Input reuse via line buffer**: The sliding 3×3 window means adjacent output positions
   share 6 of 9 input values. A 3-row line buffer (576 bytes of SRAM) stores the active
   rows of the input feature map, enabling each input pixel to be read from SRAM up to 9
   times without re-fetching from external memory.

The roofline analysis supports this architecture: at an arithmetic intensity of 45.19
FLOP/byte, the kernel is compute-bound on both the CPU and the accelerator. With 16 MAC
units operating at 100 MHz, the accelerator achieves a peak throughput of 3.2 GFLOP/s —
approximately **2.5× the measured CPU throughput** of 1.29 GFLOP/s. This speedup comes
entirely from parallelism: 16 MACs computing simultaneously vs. the CPU's effectively
single-MAC-per-cycle scalar execution.

The INT8 data format eliminates the need for floating-point hardware. Each MAC unit
requires only an 8×8→16-bit multiplier and a 32-bit accumulator, resulting in small
silicon area and low power per MAC. The quantization error from INT8 (vs. FP32) will be
measured against a PyTorch reference model to verify acceptable detection accuracy.

The AXI4-Stream interface matches the streaming nature of convolution: input rows flow in
sequentially through the line buffer, and output pixels flow out as they are computed.
AXI4-Lite provides a lightweight control plane for configuring layer dimensions and
triggering computation. The combined interface bandwidth (0.4 GB/s at 32-bit, 100 MHz)
far exceeds the data transfer requirements, ensuring the design remains compute-bound
rather than interface-bound.

