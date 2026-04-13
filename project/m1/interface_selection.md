# Interface Selection - AXI4-Stream + AXI4-Lite

## Chosen Interface
**AXI4-Stream** for data transfer (input feature maps and output feature maps),
paired with **AXI4-Lite** for control registers (layer configuration, start/done).

## Host Platform
**FPGA SoC** (e.g., Xilinx Zynq-7020 or Zynq UltraScale+). The ARM hard processor
core serves as the host CPU running pre/post-processing and detection logic. The
Conv2D accelerator is instantiated in the programmable logic (PL) fabric and connected
to the processing system (PS) via AXI interconnect.

## Bandwidth Requirement Calculation

Target: 14,468 inferences/sec (69 us per inference).

### Per-inference data transfer:

| Direction  | Data                                          | Size           |
|------------|-----------------------------------------------|----------------|
| Host to HW | Input feature map (64x64x3 INT8) | 12,288 bytes |
| Host to HW | Weights (16x3x3x3 INT8)        | 432 bytes  |
| Host to HW | Bias (16 x INT32)                         | 64 bytes    |
| HW to Host | Output feature map (64x64x16 INT8) | 65,536 bytes |

Weights and bias are loaded once at initialization (432 + 64 = 496 bytes), stored in
on-chip registers/SRAM, and reused across all inferences. Per-inference transfer is
therefore **12,288 bytes in + 65,536 bytes out = 77,824 bytes**.

### Sustained bandwidth:

| Metric                    | Value           |
|---------------------------|-----------------|
| Per-inference data        | 77,824 bytes |
| Inference time (HW)       | 69 us    |
| Required bandwidth        | 1.1259 GB/s |

### Interface rated bandwidth:

| Configuration                  | Bandwidth  |
|--------------------------------|------------|
| AXI4-Stream 32-bit @ 100 MHz  | 0.4 GB/s    |
| AXI4-Stream 64-bit @ 100 MHz  | 0.8 GB/s    |

## Bottleneck Analysis

Required sustained bandwidth (1.1259 GB/s)
is well below AXI4-Stream capacity (0.4 GB/s at 32-bit width). The design is
**not interface-bound**.

The input loading phase: 12,288 bytes must be transferred before computation
can begin. At 0.4 GB/s, loading the full input takes ~30.7 us.
This is a startup latency, not a throughput bottleneck. Once computation begins, new input
rows can stream in while the MAC array processes previously buffered rows.

## Why AXI4-Stream + AXI4-Lite

**AXI4-Stream** is chosen for the data path because convolution naturally streams: input
rows flow in sequentially, output pixels flow out as computed. The TVALID/TREADY
backpressure allows the MAC array to stall input when processing. Widely supported on
Zynq FPGA SoCs with AXI DMA IP.

**AXI4-Lite** is chosen for the control plane: simple register map for layer dimensions
(H, W, C_in, C_out, K, stride, pad), start trigger, done flag, status register.
Low-frequency access, configured once per layer.

### Alternatives considered:

| Interface | Why not                                              |
|-----------|------------------------------------------------------|
| SPI       | Only ~6 MB/s; loading 12 KB input would take ~2 ms, making the interface the bottleneck |
| I2C       | ~0.4 MB/s; completely impractical for feature map transfer |
| PCIe      | Appropriate for data-center scale but massive implementation complexity for no benefit at this data size |
| AXI4-Lite only | Could work but would require word-by-word register writes for the entire feature map -- ~3,072 write transactions for input alone |
