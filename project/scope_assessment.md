# Project Scope Assessment — CF07 Update

## Project: INT8 2D Convolution Accelerator (Weight-Stationary, AXI4 Interface)

**Target layer:** 64×64×3 input, 16 filters of 3×3×3, stride 1, padding 1 → 64×64×16 output
**Dataflow:** Weight-stationary with 16 parallel INT8 MAC units and on-chip 3-row line buffer
**Interface:** AXI4-Stream (data) + AXI4-Lite (control)

---

## CF07 Synthesis Result (CF06 Fallback — 4×4 Binary-Weight Crossbar MAC)

Since the 2D convolution accelerator core was not ready for CF07 synthesis, the CF06 fallback (`crossbar_mac.sv`) was used as a reference. Key numbers from the sky130A OpenLane 2 run:

- **Cell count:** 747 pre-PnR, 1,090 post-PnR · **Core area:** 7,967 µm²
- **Utilization:** 50.2% · **Die area:** 20,316 µm²
- **Worst setup slack (nom_tt_025C_1v80):** +0.738 ns ✅
- **Worst setup slack (nom_ss_100C_1v60):** −2.416 ns ❌ · TNS = −84.73 ns · 144 violations
- **DRC / LVS:** Clean

---

## Scope Confirmation and Adjustment

The fallback synthesis confirms that a combinational MAC-based datapath on sky130A **fails timing at the slow corner at 100 MHz** due to the unregistered adder tree depth. This is directly relevant to the 2D convolution accelerator, which also contains a deep combinational MAC accumulation path.

Based on this, the project scope is **confirmed with one targeted adjustment:**

- **Keep:** The 16-unit INT8 MAC array with weight-stationary dataflow and 3-row line buffer — this architecture is sound and the area budget (estimated 3–5× the fallback at ~25,000–40,000 µm²) fits within sky130A capabilities.
- **Add:** A pipeline register at the output of the MAC accumulation tree to cut the critical path and eliminate slow-corner setup violations. This adds one clock cycle of latency per output pixel, which is acceptable given the throughput goal.
- **Keep:** AXI4-Stream + AXI4-Lite interface — no change needed here.
- **Defer:** Multi-filter parallelism beyond 16 MACs — the timing result shows 100 MHz is already tight for combinational paths on sky130A; scaling up would worsen violations without pipelining.

Synthesis on the actual convolution core is targeted for **May 21, 2026**, before the M3 deadline of May 24.
