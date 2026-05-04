# CMAN — Systolic Array Trace (Weight-Stationary)
## ECE 410/510 · Codefest 5 · Spring 2026

**Given:**
```
A = [[1, 2],    B = [[5, 6],    Expected C = [[19, 22],
     [3, 4]]         [7, 8]]                  [43, 50]]
```

---

## (a) PE Diagram — Preloaded Weights

In weight-stationary dataflow, the weights (values from B) are preloaded into each PE before
computation begins and remain fixed throughout all cycles. Inputs stream in from the left;
partial sums flow downward from PE row 0 → row 1.

```
  Col 0 of A                    Col 1 of A
  (A[0][0], A[1][0])            (A[0][1], A[1][1]) — staggered 1 cycle
        |                              |
        v                              v
  +------------+               +------------+
  |  PE[0][0]  |               |  PE[0][1]  |   ← Row 0
  |  weight=5  |               |  weight=6  |
  |  (B[0][0]) |               |  (B[0][1]) |
  +------------+               +------------+
        | psum↓                        | psum↓
  +------------+               +------------+
  |  PE[1][0]  |               |  PE[1][1]  |   ← Row 1
  |  weight=7  |               |  weight=8  |
  |  (B[1][0]) |               |  (B[1][1]) |
  +------------+               +------------+
        ↓                             ↓
     C[*][0]                       C[*][1]
```

**Preloaded weight summary:**

| PE       | Preloaded Weight | Value |
|----------|-----------------|-------|
| PE[0][0] | B[0][0]         | **5** |
| PE[0][1] | B[0][1]         | **6** |
| PE[1][0] | B[1][0]         | **7** |
| PE[1][1] | B[1][1]         | **8** |

> Each PE computes `output = input × weight` (row 0) or `output = received_psum + input × weight`
> (row 1). The partial sum is registered between rows (1-cycle delay).

---

## (b) Cycle-by-Cycle Trace Table

**Streaming schedule:**
- **Top wire** feeds PE row 0: cycle 1 → A[0][0]=1, cycle 2 → A[1][0]=3
- **Bottom wire** feeds PE row 1: cycle 2 → A[0][1]=2, cycle 3 → A[1][1]=4 *(staggered 1 cycle)*

**Why the stagger?** When PE[0][0] computes 1×5=5 in cycle 1, that partial sum is registered and
arrives at PE[1][0] in cycle 2 — exactly when A[0][1]=2 arrives on the bottom wire. PE[1][0] then
computes 5 + 2×7 = 19 = C[0][0]. Without the stagger, the row-0 and row-1 contributions for
different output rows would mix incorrectly.

**Total cycles = 3N − 2 = 3×2 − 2 = 4 cycles for N = 2.**

| Cycle | Top input (row 0) | Bottom input (row 1) | PE[0][0] (×5)   | PE[0][1] (×6)   | PE[1][0] = psum_in + ×7 | PE[1][1] = psum_in + ×8 | C output                       |
|-------|-------------------|----------------------|-----------------|-----------------|-------------------------|-------------------------|--------------------------------|
| 1     | A[0][0] = 1       | —                    | 1×5 = **5**     | 1×6 = **6**     | 0 (no input)            | 0 (no input)            | —                              |
| 2     | A[1][0] = 3       | A[0][1] = 2          | 3×5 = **15**    | 3×6 = **18**    | **5** + 2×7 = **19**    | **6** + 2×8 = **22**    | **C[0][0]=19, C[0][1]=22**     |
| 3     | —                 | A[1][1] = 4          | 0 (no input)    | 0 (no input)    | **15** + 4×7 = **43**   | **18** + 4×8 = **50**   | **C[1][0]=43, C[1][1]=50**     |
| 4     | —                 | —                    | drain           | drain           | drain                   | drain                   | all outputs valid              |

> The bolded `5`, `6` (cycle 2) and `15`, `18` (cycle 3) entering PE row 1 are the registered
> partial sums passed down from PE row 0 in the previous cycle. PE row 0 does **not** accumulate
> across cycles — it produces a fresh product each cycle and forwards it downward.

**Verification (matches expected C exactly):**
```
C[0][0] = A[0][0]×B[0][0] + A[0][1]×B[1][0] = 1×5 + 2×7 =  5 + 14 = 19  ✓
C[0][1] = A[0][0]×B[0][1] + A[0][1]×B[1][1] = 1×6 + 2×8 =  6 + 16 = 22  ✓
C[1][0] = A[1][0]×B[0][0] + A[1][1]×B[1][0] = 3×5 + 4×7 = 15 + 28 = 43  ✓
C[1][1] = A[1][0]×B[0][1] + A[1][1]×B[1][1] = 3×6 + 4×8 = 18 + 32 = 50  ✓
```

---

## (c) Counts

### (c1) Total MAC Operations

Each of the 4 output elements C[i][j] requires 2 multiply-accumulates (one per inner-dimension
step k = 0, 1).

```
Total MACs = N × N × N = 2³ = 8
```

Counted directly from the trace:
- Cycle 1: PE[0][0] and PE[0][1] each do 1 MAC → **2 MACs**
- Cycle 2: all 4 PEs do 1 MAC each → **4 MACs**
- Cycle 3: PE[1][0] and PE[1][1] each do 1 MAC → **2 MACs**
- **Total = 8 MAC operations** ✓

### (c2) Input Reuse Count

**Matrix A — each element used N = 2 times (once per output column):**

| A element | Used in           | Reuse count |
|-----------|-------------------|-------------|
| A[0][0]=1 | C[0][0], C[0][1]  | 2× |
| A[0][1]=2 | C[0][0], C[0][1]  | 2× |
| A[1][0]=3 | C[1][0], C[1][1]  | 2× |
| A[1][1]=4 | C[1][0], C[1][1]  | 2× |

**Matrix B — each weight used N = 2 times (once per output row), and stays stationary in its PE:**

| B element | Used in           | Reuse count |
|-----------|-------------------|-------------|
| B[0][0]=5 | C[0][0], C[1][0]  | 2× |
| B[0][1]=6 | C[0][1], C[1][1]  | 2× |
| B[1][0]=7 | C[0][0], C[1][0]  | 2× |
| B[1][1]=8 | C[0][1], C[1][1]  | 2× |

**Each input value of A is reused 2 times; each weight value of B is reused 2 times.**

### (c3) Off-Chip Memory Accesses

| Tensor | Access | Count | Notes |
|--------|--------|-------|-------|
| **A**  | Read   | **4** | All 4 elements loaded once from off-chip and streamed in |
| **B**  | Read   | **4** | All 4 weights pre-loaded once at startup; never re-fetched |
| **C**  | Write  | **4** | All 4 output elements written back once computation completes |
| **Total** |     | **12**| 8 reads + 4 writes |

> Key insight: weight-stationary dataflow minimizes B (weight) memory bandwidth — weights are
> fetched from off-chip exactly once and remain in the PEs for the entire computation. This is
> especially beneficial for large weight matrices (e.g., neural-network layers).

---

## (d) Output-Stationary — One-Sentence Answer

In **output-stationary** dataflow, each PE holds and accumulates a single output element C[i][j]
fixed in place across all cycles, while both the input activations (A values) and weights (B values)
stream through the array so that the partial sum grows entirely in-register without ever moving
the accumulator off-chip.

---

## Summary

| Property                  | Value                        |
|---------------------------|------------------------------|
| Array size                | 2×2 PEs                      |
| Dataflow                  | Weight-stationary            |
| Total MACs                | 8                            |
| A input reuse factor      | 2× per element               |
| B weight reuse factor     | 2× per element (stationary)  |
| Off-chip reads (A)        | 4                            |
| Off-chip reads (B)        | 4 (preload only)             |
| Off-chip writes (C)       | 4                            |
| Total off-chip accesses   | 12                           |
| Cycles to complete        | 4 (= 3N − 2 for N = 2)       |
