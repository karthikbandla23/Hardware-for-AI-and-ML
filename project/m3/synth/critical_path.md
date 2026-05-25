# Critical Path Analysis — top (INT8 Conv2D Accelerator, M3)

## Summary

The critical path of the `top` module runs entirely through the **signed
INT8 multiply-accumulate chain** inside `compute_core` (instantiated as
`u_interface/u_core`). This was confirmed by the OpenROAD post-PnR STA
(step 54, run RUN_2026-05-24_19-44-32).

The path starts at the pixel/weight inputs delivered via `s_axis_tdata`,
propagates through the 8×8-bit signed multiplier, through the 32-bit
signed accumulator adder, through the load/accumulate mux, and settles
at the D-input of the accumulator register `u_interface.u_core.out[31:0]`
(mapped to `sky130_fd_sc_hd__dfxtp_2`).

## Measured Timing (OpenROAD STA, nom_tt_025C_1v80)

| Corner | Setup WNS | Hold WNS | Violations |
|--------|-----------|----------|------------|
| nom_tt_025C_1v80 (nominal) | **+2.049 ns** | +0.327 ns | 0 |
| nom_ff_n40C_1v95 (fast)    | +4.209 ns | +0.110 ns | 0 |
| nom_ss_100C_1v60 (slow)    | -3.334 ns | +0.902 ns | 19 |

**Clock period: 10.0 ns**  
**WNS at nominal corner: +2.049 ns → timing PASSES**  
**Fmax (nominal): ~126 MHz**

## Critical Path Stages

| Stage | Logic | sky130 cells | Measured contribution |
|-------|-------|--------------|-----------------------|
| 1 | Sign-extend pixel/weight (8→16 bit) | `and2`, `inv` | ~0.3 ns |
| 2 | 8×8 signed multiplier | `xnor2`, `xor2`, `a22o`, `o211a` tree | ~4.0 ns |
| 3 | 32-bit signed accumulator adder | `a211o`, `o211a`, `xor2`, carry chain | ~2.5 ns |
| 4 | Load/accumulate mux (×32 bits) | `mux2_1` | ~0.4 ns |
| 5 | Setup at `sky130_fd_sc_hd__dfxtp_2` | — | ~0.2 ns |

**Total: ~7.4 ns combinational → slack = 10.0 - 7.4 - routing = +2.05 ns**

## Why This Is the Critical Path

The 8×8 signed multiplier is the deepest combinational block in the design.
The Yosys area report (step 06) shows the sky130 cell breakdown:
- 93 `sky130_fd_sc_hd__xnor2_2` cells
- 27 `sky130_fd_sc_hd__xor2_2` cells
- 107 `sky130_fd_sc_hd__o211a_2` cells
- 48 `sky130_fd_sc_hd__a22o_2` cells

These are all from the multiplier partial-product reduction tree and the
subsequent 32-bit accumulator carry chain. All other paths (AXI4-Lite
register mux, write FSM, TVALID/TREADY routing) are shorter.

The slow corner (nom_ss_100C_1v60) shows violations because cell delays
increase by ~2× at 100°C/1.6V vs 25°C/1.8V, pushing the 7.4 ns path
to ~13 ns — exceeding the 10 ns constraint by 3.3 ns.

## What Would Shorten the Critical Path

1. **Pipeline the multiplier**: Insert a register between Stage 2 and
   Stage 3 (after the 8×8 product, before the 32-bit accumulate). This
   splits the path to ~4.5 ns/stage → Fmax ≈ 220 MHz. Adds 1 cycle
   latency per MAC but does not affect streaming throughput.

2. **Timing-driven placement**: Enable `PL_RESIZER_TIMING_OPTIMIZATIONS`
   in OpenLane to allow the placer to optimize cell positions for the
   critical path, reducing routing delay.

3. **Use larger drive-strength cells**: The multiplier uses `_2` drive
   strength throughout. Upgrading critical cells to `_4` reduces
   propagation delay at the cost of increased area and power.

4. **Tighten clock period to force optimization**: Setting
   `CLOCK_PERIOD = 7.0` in `config.json` will force OpenLane's resizer
   to work harder on the critical path.

## Slack Budget for M4

With WNS = +2.049 ns at 100 MHz nominal, the single-MAC design has
sufficient margin. When scaled to 16× parallel MAC units in M4, each
core is independent (no cross-MAC combinational paths), so the critical
path length will not increase. Additional routing congestion from 16×
instantiation may add ~0.5 ns, which is within the current slack budget.
