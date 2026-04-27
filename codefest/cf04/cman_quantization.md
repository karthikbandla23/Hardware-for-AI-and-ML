# CMAN — Manual INT8 Symmetric Quantization

**Course:** ECE 410/510 — Hardware for AI/ML (HW4AI), Spring 2026
**Codefest:** 4
**File:** `codefest/cf04/cman_quantization.md`

---

## Given

4×4 FP32 weight matrix W:

```
W = [  0.85, -1.20,  0.34,  2.10 ]
    [ -0.07,  0.91, -1.88,  0.12 ]
    [  1.55,  0.03, -0.44, -2.31 ]
    [ -0.18,  1.03,  0.77,  0.55 ]
```

---

## Task 1 — Scale Factor

Symmetric per-tensor quantization: `S = max(|W|) / 127`.

- **Max absolute value:** `|W[2][3]| = 2.31`
- **Scale factor:**

```
S = 2.31 / 127 = 0.01818898
```

---

## Task 2 — Quantize

Compute `W / S`, round, then clamp to `[-128, 127]`.

`W / S` (before rounding):

```
[  46.73159243, -65.97401284,  18.69263697, 115.45452250 ]
[  -3.84848408,  50.03029307, -103.35928680,   6.59740128 ]
[  85.21643325,   1.65935032, -24.19047137, -126.99997470 ]
[  -9.89610193,  56.62769435,  42.33332490,  30.23808922 ]
```

No clamping required — all values are within `[-128, 127]`.

**W_q (INT8):**

```
W_q = [  47,  -66,   19,  115 ]
      [  -4,   50, -103,    7 ]
      [  85,    2,  -24, -127 ]
      [ -10,   57,   42,   30 ]
```

---

## Task 3 — Dequantize

`W_deq = W_q × S`:

```
W_deq = [  0.85488206, -1.20047268,  0.34559062,  2.09173270 ]
        [ -0.07275592,  0.90944900, -1.87346494,  0.12732286 ]
        [  1.54606330,  0.03637796, -0.43653552, -2.31000046 ]
        [ -0.18188980,  1.03677186,  0.76393716,  0.54566940 ]
```

---

## Task 4 — Error Analysis

Per-element absolute error `|W − W_deq|`:

```
[ 0.00488206, 0.00047268, 0.00559062, 0.00826730 ]
[ 0.00275592, 0.00055100, 0.00653506, 0.00732286 ]
[ 0.00393670, 0.00637796, 0.00346448, 0.00000046 ]
[ 0.00188980, 0.00677186, 0.00606284, 0.00433060 ]
```

- **Largest error element:** `W[0][3] = 2.10` → `W_deq[0][3] = 2.09173270`
- **Largest absolute error:** **0.00826730**
- **Sum of absolute errors:** 0.06921218
- **Mean Absolute Error (MAE):** `0.06921218 / 16 =` **0.00432576**

---

## Task 5 — Bad Scale Experiment (S_bad = 0.01)

Using a too-small scale `S_bad = 0.01`.

`W / S_bad` (before clamping):

```
[  85, -120,   34,  210* ]
[  -7,   91, -188*,  12  ]
[ 155*,   3,  -44, -231* ]
[ -18,  103,   77,   55  ]
```

`*` = exceeds INT8 range, will be clamped.

**Clamping events:**

| Original `W / S_bad` | Clamped to |
|----------------------|------------|
|  210                 |  127       |
| -188                 | -128       |
|  155                 |  127       |
| -231                 | -128       |

**W_q_bad (INT8, after clamping):**

```
W_q_bad = [  85, -120,   34,  127 ]
          [  -7,   91, -128,   12 ]
          [ 127,    3,  -44, -128 ]
          [ -18,  103,   77,   55 ]
```

**W_deq_bad = W_q_bad × 0.01:**

```
W_deq_bad = [  0.85, -1.20,  0.34,  1.27 ]
            [ -0.07,  0.91, -1.28,  0.12 ]
            [  1.27,  0.03, -0.44, -1.28 ]
            [ -0.18,  1.03,  0.77,  0.55 ]
```

**Error |W − W_deq_bad|:**

```
[ 0.00, 0.00, 0.00, 0.83 ]
[ 0.00, 0.00, 0.60, 0.00 ]
[ 0.28, 0.00, 0.00, 1.03 ]
[ 0.00, 0.00, 0.00, 0.00 ]
```

- **Sum of absolute errors:** 0.83 + 0.60 + 0.28 + 1.03 = 2.74
- **MAE_bad:** `2.74 / 16 =` **0.17125**

**Comparison:** MAE increased from **0.00433** to **0.17125** — roughly **40× worse**.

**One-sentence explanation:** When S is too small, large-magnitude values in W exceed the INT8 range after division by S and get clipped to ±127/−128, permanently losing the magnitude information beyond the representable range and producing large dequantization errors at exactly the largest weights.

---

## Summary

| Quantity                 | Good scale (S = 0.01819) | Bad scale (S_bad = 0.01) |
|--------------------------|--------------------------|--------------------------|
| Clamped elements         | 0 / 16                   | 4 / 16                   |
| Largest absolute error   | 0.00827                  | 1.03                     |
| MAE                      | 0.00433                  | 0.17125                  |

---

## Deliverable Checklist

- [x] **(a)** S computation with max value shown — Task 1
- [x] **(b)** 4×4 INT8 matrix `W_q` — Task 2
- [x] **(c)** 4×4 FP32 dequantized matrix `W_deq` — Task 3
- [x] **(d)** Largest-error element identified, MAE computed — Task 4
- [x] **(e)** S_bad experiment with MAE and one-sentence explanation — Task 5
