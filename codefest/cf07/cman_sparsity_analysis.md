# CMAN — Sparsity Breakeven Analysis
**ECE 410/510 · Codefest 07 · Spring 2026**

Parameters: **N = 512**, sparsity **s** = fraction of zero elements, nnz = N²(1−s)

---

## Task 1 — Compute and Memory Expressions

### (a) Dense MVM Compute
Each of the N² elements requires one multiply and one add → 2 FLOPs per element:

$$\boxed{\text{FLOPs}_{\text{dense}} = 2N^2 = 524{,}288 \approx 500 \text{ KFLOPS}}$$

### (b) Dense Memory
All N² weights stored as FP32 (4 bytes each), no overhead:

$$\boxed{\text{Bytes}_{\text{dense}} = 4N^2 = 1{,}048{,}576 \approx 1 \text{ MB}}$$

### (c) Sparse Compute
Only the nnz = N²(1−s) non-zero elements need multiply-add. Zero entries are skipped entirely:

$$\boxed{\text{FLOPs}_{\text{sparse}} = 2N^2(1-s)}$$

### (d) Sparse Memory (CSR Format)
CSR uses three arrays:
- **values[]** — one FP32 per non-zero → 4N²(1−s) bytes
- **col_idx[]** — one INT32 per non-zero → 4N²(1−s) bytes
- **row_ptr[]** — one INT32 per row + 1 entry → 4(N+1) bytes

$$\boxed{\text{Bytes}_{\text{sparse}} = 8N^2(1-s) + 4(N+1)}$$

At s=0 (fully dense), CSR costs **2× more** than dense due to index overhead — sparse format only pays off beyond the breakeven point derived in Task 3.

---

## Task 2 — FLOPs Speedup & 2× Breakeven Sparsity

Ratio of dense FLOPs to sparse FLOPs:

$$\text{Speedup}_{\text{FLOPs}} = \frac{2N^2}{2N^2(1-s)} = \frac{1}{1-s}$$

To find the sparsity where speedup hits 2×, set the expression equal to 2:

$$\frac{1}{1-s} = 2 \implies 1-s = 0.5 \implies \boxed{s = 0.5}$$

At **50% sparsity**, sparse MVM requires exactly half the FLOPs of dense. Beyond this point, the FLOPs advantage grows rapidly (e.g., s=0.9 → 10× fewer FLOPs).

---

## Task 3 — Memory Breakeven Derivation

We want the sparsity s where CSR and dense use the same amount of memory:

$$8N^2(1-s) + 4(N+1) = 4N^2$$

Expand the left side:

$$8N^2 - 8N^2 s + 4N + 4 = 4N^2$$

Rearrange to isolate the s term:

$$8N^2 s = 4N^2 + 4N + 4$$

Solve for s:

$$s = \frac{4N^2 + 4N + 4}{8N^2} = \frac{1}{2} + \frac{1}{2N} + \frac{1}{2N^2}$$

Substituting N = 512:

$$s = \frac{1{,}048{,}576 + 2{,}048 + 4}{2{,}097{,}152} = \boxed{s_{\text{breakeven}} \approx 0.501}$$

Above s ≈ 0.501, CSR occupies less memory than the equivalent dense matrix. The breakeven is slightly above 0.5 (not exactly 0.5) because of the fixed row_ptr overhead that CSR always carries regardless of sparsity.

---

## Task 4 — End-to-End Speedup at s = 0.9 (Memory-Bandwidth-Limited)

**Assumption:** hardware perfectly skips zero MACs and their memory loads. System is bandwidth-bound at 320 GB/s.

**Dense bytes transferred:**
$$\text{Bytes}_{\text{dense}} = 4 \times 512^2 = 1{,}048{,}576 \text{ B}$$

**Sparse bytes transferred (CSR at s = 0.9, so 10% non-zeros):**
$$\text{Bytes}_{\text{sparse}} = 8 \times 512^2 \times 0.1 + 4 \times 513 = 209{,}715 + 2{,}052 = 211{,}767 \text{ B}$$

**Execution times at 320 GB/s:**
$$t_{\text{dense}} = \frac{1{,}048{,}576}{320 \times 10^9} \approx 3.28\ \mu\text{s}$$

$$t_{\text{sparse}} = \frac{211{,}767}{320 \times 10^9} \approx 0.662\ \mu\text{s}$$

**End-to-end speedup:**
$$\text{Speedup} = \frac{t_{\text{dense}}}{t_{\text{sparse}}} = \frac{1{,}048{,}576}{211{,}767} = \boxed{4.95\times}$$

The speedup is notably less than the 10× FLOPs reduction because CSR doubles the per-element memory cost (values + col_idx), cutting the effective bandwidth savings roughly in half.
