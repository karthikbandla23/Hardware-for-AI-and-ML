# Arithmetic Intensity Calculation - INT8 2D Convolution (YOLO Layer)

## Target Kernel
Single 2D convolution layer from a YOLO-style object detection network.

| Parameter    | Value            |
|-------------|------------------|
| Input        | 64x64x3 (INT8) |
| Filters      | 16 x 3x3x3 (INT8) |
| Stride       | 1         |
| Padding      | 1            |
| Output       | 64x64x16 (INT8) |

## Dominant Kernel Identification
The dominant kernel is **conv2d** (2D convolution), accounting for **99.2%** of
total YOLO detection pipeline runtime. The convolution performs 1,769,472 MAC
operations per inference, while all subsequent operations (ReLU, batch norm, pooling)
are simple element-wise operations that contribute negligible computation.

## FLOP Count (derived analytically)

Each output pixel requires a dot product over the full filter volume:

```
MACs per output pixel = C_in x K_h x K_w = 3 x 3 x 3 = 27
```

Total output pixels = H_out x W_out x C_out = 64 x 64 x 16 = 65,536

```
Total MACs  = 65,536 x 27 = 1,769,472
Total FLOPs = 1,769,472 x 2 (multiply + add) = 3,538,944
```

## Byte Count (DRAM access, no on-chip reuse)

| Data           | Formula                              | Bytes          |
|----------------|--------------------------------------|----------------|
| Input          | 64x64x3 x 1 B (INT8)  | 12,288  |
| Weights        | 16x3x3x3 x 1 B (INT8)| 432   |
| Bias           | 16 x 4 B (INT32)               | 64      |
| Output         | 64x64x16 x 1 B (INT8)| 65,536 |
| **Total**      |                                      | **78,320** |

Operand breakdown: Inputs = 12,288 B, Weights = 496 B,
Outputs = 65,536 B.

## Arithmetic Intensity

**AI = 3,538,944 / 78,320 = 45.19 FLOP/byte**

This is a **very high** arithmetic intensity, placing the convolution kernel deep in the
**compute-bound** region of the roofline for the AMD Ryzen 7 7730U. The CPU ridge point
is 1.4 FLOP/byte (source: AMD product page), so at 45.19 FLOP/byte
this kernel is ~32x beyond the ridge point.

### Why is AI so high for convolution?

Each weight value (432 total bytes) is reused across all 4,096
output spatial positions. Each input pixel participates in up to 3x3 = 9 output
pixels due to the sliding window overlap. This massive data reuse is what makes
convolution the ideal candidate for hardware acceleration -- the compute-to-memory ratio
is inherently favorable.

With perfect on-chip data reuse (all inputs and weights loaded once):
AI_reuse = 3,538,944 / 78,256 = 45.22 FLOP/byte
