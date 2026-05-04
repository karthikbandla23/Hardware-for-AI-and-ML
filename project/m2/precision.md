# Precision and Data Format

## Format chosen

**INT8 throughout the multiply path; signed INT32 accumulator.**

- `pixel`: signed 8-bit two's complement, range [-128, 127].
- `weight`: signed 8-bit two's complement, range [-128, 127].
- `product` (internal): signed 16-bit (8×8 → 16).
- `out` / accumulator: signed 32-bit two's complement.

Symmetric per-tensor quantization is used at the host-side preprocessing step,
following the formulation analyzed in CF04 CMAN: a single scale factor
`S = max(|x|) / 127` maps each FP32 tensor to the INT8 grid, and dequantization
on the output is `y_fp ≈ acc * S_x * S_w`. No bias term is fused at the
compute_core level — bias is added downstream in the +Bias / ReLU / requant
pipeline shown in the system block diagram.

## Rationale grounded in kernel and roofline

The M1 roofline analysis showed this layer has an arithmetic intensity of
**45.19 FLOP/byte**, far past both the CPU and accelerator ridge points; the
kernel is firmly compute-bound. Three properties drove the format choice:

1. **Memory traffic.** AI = 45.19 FLOP/byte in the FP32 baseline. Halving
   each operand to FP16 / BF16 doubles AI to ~90 FLOP/byte; quartering to
   INT8 quadruples it to ~180 FLOP/byte. Since the design is already
   compute-bound, the AI improvement does not change end-to-end performance
   directly — but it does compress the on-chip storage of the full filter
   bank (16 × 3 × 3 × 3 = 432 INT8 weights, vs. 1,728 bytes in FP32),
   making weight-stationary dataflow tractable in registers rather than
   SRAM. INT4 would compress further, but per-tensor INT4 quantization
   loses accuracy fast for detection layers without per-channel scaling
   (which adds hardware cost we did not budget for).

2. **Multiplier area / power.** A signed 8×8 → 16 multiplier is roughly
   16× smaller and much lower power than an FP32 multiplier, and ~4×
   smaller than a BF16 multiplier. This is what makes the 16-MAC array
   (one MAC per output filter, all running in parallel) fit the chiplet
   area and 100 MHz target. Anything larger than INT8 would require us
   to reduce the parallelism factor and lose the headline 2.5× speedup
   over the CPU baseline that the M1 roofline projects.

3. **Accumulator headroom.** The kernel accumulates K_TOTAL = 27 INT8
   products. Worst case `|product| ≤ 127 × 128 = 16,256`, and worst-case
   `|sum|` over 27 taps is 27 × 16,256 = 438,912 — well below 2^31 = 2.15B.
   A 32-bit signed accumulator gives us ~12 bits of headroom over the
   tightest bound and avoids any saturation logic. CF04 CLLM observed
   that two's-complement wrap is harmless when overflow cannot be
   reached. INT16 would only have ~3 bits of headroom and would need
   per-tap bounds checks; INT64 is wasteful. INT32 is the right size.

## Quantization error analysis

The harness `sim/quantization_error.py` draws **N = 200** random 3×3×3
windows in FP32, quantizes them with per-tensor symmetric INT8 scales,
streams the quantized values through the actual compiled `compute_core`
(via Icarus Verilog), captures the raw 32-bit accumulator, dequantizes
the result back to FP32, and compares against the FP32-domain dot
product of the original (unquantized) tensors. Stimulus is drawn with
seed `0xC0FFEE` for reproducibility.

| Metric                                          | Value     |
|-------------------------------------------------|-----------|
| Windows tested                                  | 200       |
| DUT integer accumulator vs `numpy` integer ref  | **exact match** |
| Mean absolute error (vs FP32 ref)               | 0.0068    |
| Max  absolute error                             | 0.0269    |
| 99th-pct absolute error                         | 0.0261    |
| Mean relative error                             | 2.42%     |
| 99th-pct relative error                         | 36.2%     |
| Max  relative error                             | 126.1%    |

The "DUT integer accumulator vs numpy integer ref: exact match" line is
the most important: it confirms there is no integer-arithmetic bug
between INT8 inputs and the INT32 sum-of-products. All FP32 error
therefore comes from the quantization rounding step itself, not from
the hardware path.

The high tail in the relative-error distribution is an artifact of
small-denominator divisions: when the FP32 reference happens to land
near zero (the 27 signed products partially cancel), even an absolute
error of 0.02 produces a large percentage. The absolute-error
distribution is the trustworthy view, and its p99 of 0.026 is well
within the symmetric-quantization noise floor predicted by `S × S` ≈
(1/127)² ≈ 6×10⁻⁵ per-tap, ×27 taps ≈ 1.7×10⁻³ minimum noise — the
observed p99 sits about an order of magnitude above this floor, consistent
with rounding accumulation across 27 taps.

## Statement of acceptability

The error is acceptable for this application. INT8 post-training
quantization for YOLO-class detection layers has been shown by Jacob et
al. (Google's quantization-aware-training paper, CVPR 2018) and the
TensorRT INT8 calibration documentation to keep mAP loss below 1
percentage point on COCO when per-tensor symmetric scaling is applied
to convolutional layers — and the layer modeled here is in the
detection head, not a sensitive depthwise / squeeze-and-excite path.
Our measured mean relative error of 2.4% on raw pre-activation
accumulators is well below the per-output-pixel tolerance budget of
this layer: the post-conv ReLU clips negative values to 0, removing
sub-bias noise; the requantize-back-to-INT8 step then re-grids to the
nearest of 256 levels, absorbing absolute errors below ~S_y / 2. Given
that S_y in this layer is on the order of the per-channel maximum
divided by 127, an absolute pre-activation error of 0.027 is below the
INT8 output's own quantization step in most channels, so the error is
entirely absorbed by the output requantization rather than reaching
later layers.

We accept the format. Future work (M3) will revisit per-channel
weight scaling if measured detection accuracy on a held-out validation
set drops by more than 1 mAP point relative to the FP32 reference.
