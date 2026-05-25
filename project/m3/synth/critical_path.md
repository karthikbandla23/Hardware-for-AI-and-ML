# Critical Path Analysis — top (INT8 Conv2D Accelerator, M3)

## Summary

The critical path of the `top` module runs entirely through the **signed
INT8 multiply-accumulate chain** inside `compute_core` (instantiated as
`u_interface/u_core`). The path starts at the registered output of the
AXI4-Stream input register (`s_axis_tdata[15:0]`, which delivers `pixel`
and `weight` to the multiplier combinationally), propagates through the
8×8-bit signed multiplier, through the 32-bit signed accumulator adder,
through the load/accumulate mux, and settles at the D-input of the
accumulator register `u_interface.u_core.out[31:0]`
(Yosys FF: `$flatten\u_interface.\u_core.$procdff$298`, type `$_SDFFE_PN0P_`).

## Path Stages and Logic Depth

| Stage | Logic | Gates (Yosys type) | Est. delay (sky130 typ) |
|-------|-------|--------------------|-------------------------|
| 1 | Sign-extend pixel/weight (8→16 bit) | `$_AND_` / `$_NOT_` (1 level) | ~0.3 ns |
| 2 | 8×8 signed multiplier (`$macc` → ABC mapped) | `$_XOR_`, `$_ANDNOT_`, `$_OR_` carry chain (~8 levels) | ~4.0 ns |
| 3 | 32-bit signed accumulator `$alu` (carry-lookahead, LCU WIDTH=32) | `$_XOR_`, `$_OR_`, `$_ANDNOT_` (~5 LCU levels) | ~2.5 ns |
| 4 | Load/accumulate mux `$_MUX_` ×32 (controlled by `done` or `count==K_TOTAL`) | `$_MUX_` (1 level) | ~0.4 ns |
| 5 | Setup time at D-input of `$_SDFFE_PN0P_` (out register) | — | ~0.2 ns |

**Total combinational depth: ~7.4 ns**  
**Clock period constraint: 10.0 ns**  
**Estimated WNS: +2.6 ns → timing passes at 100 MHz**

## Why This Is the Critical Path

The 8×8 signed multiplier is the deepest combinational block in the design.
After ABC optimization (`dretime + map` using the 13-gate generic library),
Yosys reports 200 `$_XOR_` cells and 389 `$_ANDNOT_` cells — the vast
majority of which belong to the multiplier's partial-product reduction tree
(Booth-style carry-save or ripple-carry implementation). The subsequent
32-bit accumulator adds another two carry-chain stages. All other paths in
the design — the AXI4-Lite register mux (~4 ns), the write-FSM (~2 ns), the
TVALID/TREADY routing (~1 ns) — are shorter and do not appear on the critical
path.

## What Would Shorten It

1. **Pipeline the multiplier.** Inserting a register between Stage 2 and
   Stage 3 (after the 8×8 product, before the 32-bit accumulator add) would
   split the critical path roughly in half: ~4.3 ns/stage, giving Fmax ≈ 230 MHz.
   This adds one cycle of pipeline latency per MAC but does not affect throughput
   for the back-to-back streaming use case.

2. **Use a DSP block.** On the Zynq-7020 FPGA target, replacing the inferred
   multiplier with an explicit `DSP48E1` instantiation would reduce the
   multiply-accumulate path to a single pipelined DSP stage (registered
   inputs, registered output), easily meeting a 200 MHz clock. For the ASIC
   (sky130) path, using a hard-macro multiplier cell would achieve the same
   effect.

3. **Widen the accumulator register enable.** The `$_SDFFE_PN0P_` cell adds
   ~0.2 ns setup overhead because the enable (`in_valid` combined with the
   load/accumulate mux select) goes through additional logic. Restructuring
   the enable tree to reduce its depth would recover ~0.2 ns.

## Slack Budget for M4

With an estimated WNS of +2.6 ns at 100 MHz, the design has sufficient slack
for the single-MAC core. When the full 16-MAC parallel array is integrated
in M4, each MAC unit will be independent (no cross-MAC combinational paths),
so the critical path length is not expected to grow. The additional area and
fanout of the 16× instantiation may increase routing delay by ~0.5–1.0 ns,
which is within the current slack budget.
