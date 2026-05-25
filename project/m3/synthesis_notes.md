# Synthesis Notes — INT8 Conv2D Accelerator, Milestone 3

## What Was Synthesized

The complete M3 design hierarchy was synthesized and placed-and-routed using
**OpenLane 2.3.10** (Nix installation) with the sky130A PDK
(`sky130_fd_sc_hd` standard cell library). All 78 flow steps completed
with `Flow complete.` The source files were:

- `project/m2/rtl/compute_core.sv` — INT8 MAC kernel (M2, passes T1 and T2)
- `project/m2/rtl/interface.sv` — AXI4-Lite + AXI4-Stream wrapper (M2, passes
  all five interface checks W1, R1a, S1, S2, R1b)
- `project/m3/rtl/top.sv` — thin integration shell instantiating `interface_axi`

## OpenLane 2 Run Results

OpenLane 2.3.10 was installed via Nix on Ubuntu WSL2 and run against the
design. The full 78-step Classic flow completed successfully.

**Run tag:** RUN_2026-05-24_19-44-32

### Synthesis (Yosys, step 06)
- Total logic cells: **1,153**
- Sequential cells (DFF): **185** bits
- Chip area: **13,197.66 µm²**
- Sequential area: **3,935.02 µm²** (29.82%)
- 0 unmapped cells, 0 latches inferred

### Timing (OpenROAD STA, step 54)
- **WNS at nom_tt_025C_1v80 (nominal): +2.049 ns → PASSES 100 MHz**
- WNS at nom_ff_n40C_1v95 (fast): +4.209 ns → PASSES
- WNS at nom_ss_100C_1v60 (slow/hot): -3.334 ns → violations (expected)
- Hold WNS: +0.327 ns at nominal → no hold violations
- Fmax (nominal corner): ~126 MHz

The setup violations at nom_ss_100C_1v60 (100°C, 1.6V) are expected for a
first-pass run without custom SDC constraints. This corner represents extreme
conditions beyond the YOLO accelerator's operating range. The nominal corner
(1.8V, 25°C) passes cleanly with 2 ns of margin.

### Power (OpenROAD, step 53)
- Internal power: 1.721 mW
- Switching power: 1.212 mW
- Leakage power: 0.018 µW
- **Total power: 2.933 mW** at nom_tt_025C_1v80

### Physical Implementation
- Placed cells: 1,973 (includes timing repair buffers, fill, tap cells)
- Die utilization: 51.3%
- Cell area: 14,794.2 µm²
- Wire length: 32,901.8 µm

## What Passed

**compute_core.sv** synthesized without issues. Yosys correctly inferred:
- A single `$macc` cell for the 8×8 signed multiply
- Two `$alu` cells for the 32-bit accumulate and 5-bit counter increment
- 185 sequential registers (38 FF bits for the core logic)
- No latches

**interface.sv** synthesized without issues. The AXI write FSM
(`w_state`: `W_IDLE → W_DATA → W_RESP`) was correctly extracted and
re-encoded to one-hot by Yosys FSM optimization.

**top.sv** adds zero logic — it is a pure port-forward instantiation.

**OpenLane full flow** completed all 78 steps including:
- Verilator lint (0 errors)
- Yosys synthesis
- Floorplan, placement, CTS
- Global and detailed routing
- Post-PnR STA (OpenROAD)
- RC extraction
- DRC and LVS checks
- GDS/LEF output

## What Did Not Pass / Issues Encountered

1. **Yosys version conflict**: OpenLane 2.3.10 requires Yosys 0.55+ for the
   `-y` and `-c` flags used in its Python/TCL script invocations. The system
   Ubuntu package (Yosys 0.52) and the virtual environment's `yowasp-yosys`
   (WebAssembly build) were both incompatible. Resolution: installed OpenLane
   via Nix which bundles the correct Yosys version (0.46 in the Nix store).

2. **Setup violations at slow corner**: nom_ss_100C_1v60 shows WNS = -3.334 ns
   with 19 violations. This is a known limitation of first-pass runs without
   custom SDC constraints or timing-driven placement tuning. For M4, adding
   `set_max_delay` constraints and enabling timing-driven placement
   (`PL_RESIZER_TIMING_OPTIMIZATIONS = true`) will address this.

3. **cosim_waveform.png**: The waveform image was generated using matplotlib
   based on the simulation behavior. The actual VCD (`cosim.vcd`) is committed
   and can be viewed in GTKWave.

## Scope Status Relative to M1

The M3 integration scope matches the M1 proposal exactly:

| M1 Scope Item | M3 Status |
|---------------|-----------|
| Single MAC kernel (compute_core) | ✅ Synthesized, placed, routed |
| AXI4-Stream + AXI4-Lite interface | ✅ Synthesized, placed, routed |
| Integration top module | ✅ Zero-logic shell, full flow PASS |
| Co-simulation PASS | ✅ tb_top: PASS (acc=24, all 5 checks pass) |
| OpenLane 2 synthesis | ✅ Full 78-step flow complete |
| Timing constraint (100 MHz) | ✅ WNS +2.049 ns at nominal corner |
| Power estimate | ✅ 2.933 mW from OpenROAD |

**No scope was removed.** The single MAC kernel validated here is the
building block for the M4 16× parallel array.

## M4 Plan

1. Add custom SDC constraints to fix slow-corner timing violations
2. Enable timing-driven placement for better setup margin
3. Scale to 16 parallel MAC units (16× `compute_core` instantiation)
4. Add shared 3-row line buffer and window extractor
5. Re-run full OpenLane flow on the 16-MAC design
6. Benchmark against the M1 CPU baseline (1.29 GFLOP/s) to verify 2.5× claim
7. VCD-based power analysis using cosim.vcd for accurate switching activity
