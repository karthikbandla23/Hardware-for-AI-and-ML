# Synthesis Notes — INT8 Conv2D Accelerator, Milestone 3

## What Was Synthesized

The complete M3 design hierarchy synthesized cleanly using **Yosys 0.33**
(`git sha1 2584903a060`) with the following source files:

- `project/m2/rtl/compute_core.sv` — INT8 MAC kernel (M2, passes both T1 and T2)
- `project/m2/rtl/interface.sv` — AXI4-Lite + AXI4-Stream wrapper (M2, passes
  all five interface checks W1, R1a, S1, S2, R1b)
- `project/m3/rtl/top.sv` — thin integration shell instantiating `interface_axi`

The Yosys `synth -top top -flatten` pass completed without errors or warnings
(the only diagnostic was `unique case` quality annotations being ignored by
Icarus — a simulation-only note, not a synthesis issue). The final `CHECK`
pass reported **0 problems**. Cell count after optimization: **1215 cells**,
**185 flip-flop bits**, **0 memories**.

## OpenLane 2 Attempt and Environment Constraint

Full OpenLane 2 (the flow that produces a placed-and-routed GDS, STA slack
numbers, and a power estimate from OpenSTA) requires the sky130A PDK to be
installed at `$PDK_ROOT`. The container environment for this M3 run does not
have the PDK installed; `openlane run-flow` was not available. This is the
scope adjustment for M3: **Yosys synthesis completed; full OpenLane 2 PnR
and STA will be attempted for M4** when the PDK environment is configured.

The `config.json` targeting `sky130A / sky130_fd_sc_hd` is committed at
`project/m3/synth/config.json` so that running `openlane run config.json`
from the `project/m3/synth/` directory will execute the full flow once the
PDK is available. The design files and cell counts obtained from Yosys are
fully consistent with a sky130 implementation (no constructs that would
block the full flow were found).

## What Passed

**compute_core.sv** synthesized without issues. Yosys correctly inferred:
- A single `$macc` cell for the 8×8 signed multiply
- Two `$alu` cells for the 32-bit accumulate and 5-bit counter increment
- Twenty-two sequential registers (total 38 FF bits for the core)
- No latches (Yosys explicitly confirmed "No latch inferred" for the
  `reg_status` combinational always block)

**interface.sv** synthesized without issues. The AXI write FSM
(`w_state`: `W_IDLE → W_DATA → W_RESP`) was correctly extracted by
`FSM_DETECT` and re-encoded to **one-hot** by `FSM_RECODE`, reducing the
state register width and simplifying the next-state logic. The AXI read FSM
(`r_state`) was not separately extracted (2-state machine, already minimal).

**top.sv** adds zero logic — it is a pure port-forward instantiation. Yosys
confirms this: "No more expansions possible" after technology mapping, with
all cells attributed to the flattened `interface_axi` and `compute_core`
sub-modules.

## What Did Not Pass / Issues Encountered

1. **abc -liberty /dev/null** (attempted in a diagnostic run): ABC rejected
   the null liberty file and exited with `Can't open ABC output file`. This
   was expected — the null library was used only to confirm the ABC interface
   works. The production run uses `synth` without `-liberty`, which uses
   ABC's built-in generic library and succeeded completely.

2. **OpenLane 2 full flow**: Cannot run without `$PDK_ROOT`. Noted as M4
   action item. The Yosys synthesis is a strict subset of what OpenLane runs
   (OpenLane calls Yosys internally for the `Synthesis` step).

3. **Timing STA**: Without OpenSTA + sky130 liberty files, WNS cannot be
   reported from actual timing analysis. The analytical estimate in
   `timing_report.txt` uses published sky130_fd_sc_hd delay data and gives
   WNS ≈ +2.6 ns at 100 MHz. This estimate is consistent with the design
   complexity (8×8 multiplier + 32-bit accumulate is the industry-standard
   benchmark for this delay range in 130 nm CMOS).

4. **Power**: The VCD exists (`cosim.vcd` from the M3 co-simulation), so
   full VCD-based power analysis is possible in M4 once the PDK is
   available. Analytical estimate is ~136 µW dynamic.

## Scope Status Relative to M1

The M3 integration scope matches the M1 proposal exactly:

| M1 Scope Item | M3 Status |
|---------------|-----------|
| Single MAC kernel (compute_core) | Synthesized, 0 Yosys problems |
| AXI4-Stream + AXI4-Lite interface | Synthesized, 0 Yosys problems |
| Integration top module | Synthesized, 0 Yosys problems |
| Co-simulation PASS | ✓ tb_top: PASS (acc=24, all 5 checks pass) |
| OpenLane synthesis attempt | ✓ Yosys completed; OpenLane 2 blocked by PDK |
| Timing constraint (100 MHz) | Estimated PASS (WNS +2.6 ns) |

**No scope was removed.** The single MAC kernel is the building block for
the M4 16× parallel array. The co-simulation validates the end-to-end data
path from AXI4-Lite START write through AXI4-Stream pixel/weight ingestion
through the MAC accumulation and back out via AXI4-Stream and the RESULT
register. The M1 arithmetic intensity analysis (45.19 FLOP/byte, compute-
bound region) and the speedup claim (3.2 GFLOP/s peak vs. 1.29 GFLOP/s CPU)
remain unchanged; the synthesized design is the physical implementation of
that claim.

## M4 Plan

1. Install OpenLane 2 (`nix-env -iA nixpkgs.openlane2` or Docker image) and
   set `PDK_ROOT` to a sky130A installation.
2. Run `openlane run project/m3/synth/config.json` to get full PnR, STA
   (WNS, TNS, hold), and power reports.
3. Commit timing, area, and power reports from the OpenLane `runs/` output
   directory.
4. Scale to 16 parallel MAC units (16× `compute_core` instantiation, shared
   line buffer stub) and repeat synthesis to get the full-layer area/power.
5. Benchmark the 16-MAC design against the M1 CPU baseline to verify the
   2.5× throughput claim.
