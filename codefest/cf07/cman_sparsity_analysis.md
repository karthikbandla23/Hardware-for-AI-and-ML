# CMAN — Sparsity breakeven analysis

**N = 512**, sparsity **s** (fraction of zeros), nnz = N²(1−s)

---

## Task 1 — Expressions

**(a) Dense MVM compute**

$$\text{FLOPs}_{\text{dense}} = 2N^2$$

**(b) Dense memory**

$$\text{Bytes}_{\text{dense}} = 4N^2$$

**(c) Sparse compute**

$$\text{FLOPs}_{\text{sparse}} = 2N^2(1-s)$$

**(d) Sparse memory (CSR)**

CSR stores: values (FP32, 4 B each), col\_idx (INT32, 4 B each), row\_ptr (INT32, 4 B × (N+1))

$$\text{Bytes}_{\text{sparse}} = 8N^2(1-s) + 4(N+1)$$

---

## Task 2 — FLOPs speedup and 2× breakeven

$$\text{Speedup}_{\text{FLOPs}} = \frac{2N^2}{2N^2(1-s)} = \frac{1}{1-s}$$

Set equal to 2:

$$\frac{1}{1-s} = 2 \implies \boxed{s = 0.5}$$

---

## Task 3 — Memory breakeven

Set sparse bytes = dense bytes:

$$8N^2(1-s) + 4(N+1) = 4N^2$$

$$8N^2 - 8N^2 s = 4N^2 - 4(N+1)$$

$$8N^2 s = 4N^2 + 4N + 4$$

$$s = \frac{4N^2 + 4N + 4}{8N^2} = \frac{1}{2} + \frac{1}{2N} + \frac{1}{2N^2}$$

For N = 512:

$$s = \frac{1{,}048{,}576 + 2{,}048 + 4}{2{,}097{,}152} = \boxed{0.501}$$

Above this sparsity, CSR uses less memory than dense.

---

## Task 4 — End-to-end speedup at s = 0.9, memory-bandwidth-limited

$$\text{Bytes}_{\text{dense}} = 4 \times 512^2 = 1{,}048{,}576 \text{ B}$$

$$\text{Bytes}_{\text{sparse}} = 8 \times 512^2 \times 0.1 + 4 \times 513 = 209{,}715 + 2{,}052 = 211{,}767 \text{ B}$$

$$\text{Speedup} = \frac{1{,}048{,}576}{211{,}767} = \boxed{4.95\times}$$
