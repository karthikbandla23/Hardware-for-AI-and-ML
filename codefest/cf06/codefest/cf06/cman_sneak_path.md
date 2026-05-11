# CMAN — Sneak Paths in a Resistive Crossbar
**ECE 410/510 — Codefest 6 | Spring 2026**

---

## Circuit Overview

A 2×2 resistive crossbar where rows are voltage inputs and columns sense output currents:

```
             col 0          col 1
             
V_row0 ──── R[0][0]=1kΩ ── R[0][1]=2kΩ ──── (V_col1)
             
(V_row1) ── R[1][0]=2kΩ ── R[1][1]=1kΩ ──── 0V (sense)
             │
             0V
```

Low-resistance (1 kΩ) = ON weight, High-resistance (2 kΩ) = OFF weight.

---

## Task 1 — Ideal Read

**Applied conditions:**
- V_row0 = 1 V, V_col0 = 0 V (virtual ground)
- V_row1 = 0 V, V_col1 = 0 V (both grounded)

With row 1 and col 1 grounded, the only active path into col 0 is straight through R[0][0]:

$$I_{col0} = \frac{V_{row0}}{R[0][0]} = \frac{1\,\text{V}}{1\,\text{k}\Omega} = \boxed{1\,\text{mA}}$$

---

## Task 2 — Sneak Path Read

**Applied conditions:**
- V_row0 = 1 V, V_col0 = 0 V
- V_row1 and V_col1 both **floating** (undriven)

Now all four resistors are active. Current can leak from row 0 through the off-path cells into the floating nodes and back into col 0 — this is the sneak path.

### Setting up KCL

Two unknown node voltages: V_row1 and V_col1.

**KCL at V_row1** — currents leaving the node sum to zero:

$$\frac{V_{row1}}{R[1][0]} + \frac{V_{row1} - V_{col1}}{R[1][1]} = 0$$

$$\frac{V_{row1}}{2k} + \frac{V_{row1} - V_{col1}}{1k} = 0$$

Multiply by 2k:

$$V_{row1} + 2V_{row1} - 2V_{col1} = 0 \implies 3V_{row1} = 2V_{col1}$$

$$\therefore\quad V_{row1} = \frac{2}{3}\,V_{col1} \tag{1}$$

**KCL at V_col1** — currents leaving the node sum to zero:

$$\frac{V_{col1} - V_{row0}}{R[0][1]} + \frac{V_{col1} - V_{row1}}{R[1][1]} = 0$$

$$\frac{V_{col1} - 1}{2k} + \frac{V_{col1} - V_{row1}}{1k} = 0$$

Multiply by 2k:

$$V_{col1} - 1 + 2V_{col1} - 2V_{row1} = 0 \implies 3V_{col1} - 2V_{row1} = 1 \tag{2}$$

### Solving (1) into (2):

$$3V_{col1} - 2 \cdot \frac{2}{3}V_{col1} = 1 \implies \frac{5}{3}V_{col1} = 1$$

$$\boxed{V_{col1} = 0.6\,\text{V}, \qquad V_{row1} = 0.4\,\text{V}}$$

### Actual I_col0

Two current contributions flow into col 0:

| Current path | Calculation | Value |
|---|---|---|
| Direct — R[0][0] | (1 − 0) / 1 kΩ | 1.0 mA |
| Sneak — R[1][0] | (0.4 − 0) / 2 kΩ | 0.2 mA |
| **I_col0 total** | | **1.2 mA** |

The sneak path adds a **20% error** over the ideal read.

---

## Task 3 — Why Sneak Paths Corrupt MVM

When row 1 and col 1 are left floating, resistors R[0][1], R[1][1], and R[1][0] form an unintended current divider that injects extra current into col 0. This additional current has nothing to do with the intended weight R[0][0], so the column no longer purely represents the dot product — the MVM result is corrupted. As the crossbar scales to N×N, the number of possible sneak paths grows rapidly, compounding the error and making large analog crossbar arrays increasingly inaccurate without per-cell selector devices or active column biasing to suppress leakage.
