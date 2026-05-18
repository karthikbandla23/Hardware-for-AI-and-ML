# Synthesis Interpretation — crossbar_mac (CF06 Fallback)
**Tool:** OpenLane 2.3.10 · **PDK:** sky130A · **Target Clock:** 10 ns (100 MHz)

---

## (a) Clock Period and Worst-Case Slack

The design was synthesized at a **10 ns clock period (100 MHz)**. At the nominal timing corner (nom_tt_025C_1v80), the worst-case setup slack is **+0.738 ns**, meaning the design meets timing comfortably under typical conditions. However, at the slow-speed corner (nom_ss_100C_1v60 — slow transistors, high temperature, low voltage 1.6V), the worst-case setup slack degrades to **−2.416 ns**, with a total negative slack (TNS) of **−84.73 ns** across **144 violating endpoints**. The design passes timing at typical and fast corners but fails at slow-speed corners, which is common for combinational-heavy datapaths on sky130A at 100 MHz.

---

## (b) Critical Path

The critical path ends at **out_flat[46]** (observed throughout the placement optimization log). The design is purely combinational between the weight registers and outputs — the path starts from the **weight[] flip-flops (dfstp_2)**, passes through the signed add/subtract tree built from `xor2`, `xnor2`, `mux2`, `and2`, `or2`, and multi-input AND-OR cells, and terminates at the output register or output port. The dominant cell types along the path are:

- **sky130_fd_sc_hd__mux2_1** (124 instances) — the largest contributor, used for the ±1 weight selection
- **sky130_fd_sc_hd__xor2_2** (95 instances) — sign-extension and addition logic
- **sky130_fd_sc_hd__xnor2_2** (75 instances) — complementary addition logic
- **sky130_fd_sc_hd__and2_2** (59 instances) — carry/masking logic

The depth of this combinational chain is what causes the slow-corner slack violations — the 4×4 dot product accumulates ~8 levels of logic through the MUX-adder tree.

---

## (c) Total Cell Area and Top Contributors

- **Total chip area:** 7,967.64 µm² (post-synthesis) · **Core utilization:** 50.2%
- **Die area:** 20,316 µm² · **Core area:** 15,770 µm²
- **Total standard cell instances (post-PnR):** 1,090

Top three contributors by instance count:

| Cell | Count | Role |
|------|-------|------|
| `sky130_fd_sc_hd__mux2_1` | 124 | Weight ±1 selection per MAC element |
| `sky130_fd_sc_hd__xor2_2` | 95 | Signed addition / XOR logic |
| `sky130_fd_sc_hd__xnor2_2` | 75 | Complementary addition logic |

Sequential elements (`dfstp_2` flip-flops) account for only **16 instances (5.28%)** of the pre-PnR cell count, confirming the design is overwhelmingly combinational.

---

## (d) Failed Constraints, Violations, and Warnings Worth Investigating

**Setup violations at slow corner:** 48 endpoints fail setup at `nom_ss_100C_1v60` and `max_ss_100C_1v60`, with WNS = −2.416 ns and TNS = −84.73 ns. The resizer could not repair all violations (`RSZ-0062`). This is the most significant issue — the combinational dot-product path is too deep for 100 MHz under worst-case PVT.

**No SDC file provided:** OpenROAD fell back to a generic SDC (`PNR_SDC_FILE` not defined), which means input arrival times and output load constraints were not modeled. Real timing could be worse once proper IO constraints are applied.

**DRC clean:** `magic__drc_error__count = 0` and `klayout__drc_error__count = 0` — the layout is DRC-clean.

**LVS clean:** All LVS checks pass with zero mismatches.

**No hold violations** at any corner — hold timing is fully met.
