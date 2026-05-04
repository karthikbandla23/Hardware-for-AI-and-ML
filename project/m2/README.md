# Milestone 2 — INT8 Conv2D Accelerator

This folder contains the M2 deliverables for the ECE 410/510 HW4AI Spring 2026
project: an INT8 2D convolution accelerator chiplet targeting one YOLO-style
detection layer (64×64×3 → 64×64×16, 16 filters of 3×3×3, weight-stationary
dataflow with 16 parallel INT8 MAC units).

The core compute kernel and the AXI4 interface module are both implemented as
synthesizable SystemVerilog and verified against an independent reference.

## Files

```
m2/
├── rtl/
│   ├── compute_core.sv     INT8 MAC accumulator (single MAC, replicated 16× in M3)
│   └── interface.sv        AXI4-Lite (control) + AXI4-Stream (data) wrapper
├── tb/
│   ├── tb_compute_core.sv  Two-vector compute-core testbench (Sobel-x + mixed-sign)
│   └── tb_interface.sv     AXI4-Lite write+read + 27-beat stream testbench
├── sim/
│   ├── compute_core_run.log    PASSing transcript of tb_compute_core
│   ├── interface_run.log       PASSing transcript of tb_interface
│   ├── waveform.png            Annotated representative waveform (T1 window)
│   ├── render_waveform.py      VCD → PNG renderer used to produce waveform.png
│   ├── quantization_error.py   200-sample DUT-vs-FP32 error harness
│   └── quantization_error.log  Transcript of the harness
├── precision.md            Numerical format choice + error analysis
├── precision_summary.json  Machine-readable summary cited by precision.md
└── README.md               this file
```

## Tools used

| Tool             | Version | Purpose                                       |
|------------------|---------|-----------------------------------------------|
| Icarus Verilog   | 12.0    | Compile & simulate SystemVerilog (`iverilog`, `vvp`) |
| Python           | ≥ 3.10  | Quantization-error harness, waveform renderer |
| numpy            | ≥ 1.24  | FP32 reference & integer cross-check          |
| matplotlib       | ≥ 3.7   | `waveform.png` rendering                      |

Install on Ubuntu 24.04:

```bash
sudo apt-get update && sudo apt-get install -y iverilog gtkwave
python3 -m pip install --user numpy matplotlib
```

## Reproduce M2 — short version

```bash
# from the repo root
cd project/m2

# 1. Compute-core sim (PASS)
iverilog -g2012 -o sim/tb_compute_core.vvp rtl/compute_core.sv tb/tb_compute_core.sv
(cd sim && vvp tb_compute_core.vvp | tee compute_core_run.log)

# 2. Interface sim (PASS)
iverilog -g2012 -o sim/tb_interface.vvp rtl/compute_core.sv rtl/interface.sv tb/tb_interface.sv
(cd sim && vvp tb_interface.vvp | tee interface_run.log)

# 3. Re-render the representative waveform from the dumped VCD
(cd sim && python3 render_waveform.py compute_core.vcd waveform.png)

# 4. Re-run the 200-sample quantization-error analysis
(cd sim && python3 quantization_error.py | tee quantization_error.log)
```

Each testbench prints a final `PASS` line that the grader can grep for; the
transcripts in `sim/*_run.log` are the committed copies of those runs.

## What each testbench does

### `tb_compute_core.sv` — two test vectors

* **T1 — representative kernel from M1 profiling.** A 3×3×3 (K_TOTAL = 27)
  Sobel-x convolution. Three input channels, each holding the patch
  `[[1,2,3],[4,5,6],[7,8,9]] + ch×10`, are convolved with the Sobel-x kernel
  `[[-1,0,1],[-2,0,2],[-1,0,1]]` per channel. Per-channel response is +8
  (the textbook horizontal-gradient sum); total over 3 channels is **24**.
  The expected value is computed inside the testbench from the same arrays
  using SystemVerilog signed arithmetic — never read back from the DUT.
* **T2 — deterministic mixed-sign 27-tap stream.** A linear-congruential
  sequence spanning the INT8 range. Exercises sign-extension and the 32-bit
  accumulator headroom (final value 32,853, a value that would silently
  corrupt under any 16-bit accumulator implementation).

The testbench checks both the value of `out` and the assertion of `done`
exactly once per K_TOTAL beats. Back-to-back windows are run with no
intervening reset to verify the DUT's start-of-window detection.

### `tb_interface.sv` — full AXI4 transactions

* **W1** — full AXI4-Lite write transaction to `CTRL` (offset 0x0): drives
  AWVALID/AWADDR + WVALID/WDATA, waits for AWREADY/WREADY, captures the
  response on the B channel. Verifies `BRESP == OKAY (2'b00)`.
* **R1a** — AXI4-Lite read of `STATUS` (offset 0x4) immediately after START.
  Verifies `STATUS[1] == BUSY == 1`.
* **S1** — 27-beat AXI4-Stream input on `s_axis`. TVALID/TREADY handshake on
  every beat; `TLAST` asserted on beat 27.
* **S2** — one-beat AXI4-Stream output on `m_axis`. Checks `TDATA == 24`,
  `TLAST == 1`, and the value matches the in-TB independent reference.
* **R1b** — AXI4-Lite read of `RESULT` (offset 0xC). Cross-checks the
  AXI4-Stream output against the readable register copy.

### Quantization-error harness

`sim/quantization_error.py` generates a temporary harness that streams 200
randomly drawn 3×3×3 INT8 windows through the actual compiled `compute_core`,
captures each accumulator, and compares the dequantized output against an
FP32-domain reference. Numbers and methodology are documented in
`../precision.md`.

## Deviations from M1

* **No interface change.** The M1 selection was AXI4-Stream + AXI4-Lite; M2
  implements exactly that. No update to `project/m1/interface_selection.md` is
  needed.
* **No precision change.** M1 specified INT8 multiply / INT32 accumulate; M2
  implements that and provides the optional error analysis in `precision.md`.
* **Module file naming.** The M1 stub `conv2d_core.v` is promoted to
  `compute_core.sv` to match the M2 grader-expected filename (`compute_core.sv`).
  The contents are functionally equivalent: same ports (with the addition of
  IN_CHANNELS so K_TOTAL = K×K×C_in correctly = 27 for the 3×3×3 layer),
  same single-clock synchronous reset, same INT8 → INT32 datapath. The
  earlier cocotb test `../m1/test_conv2d_core.py` is preserved for reference;
  the SystemVerilog testbench `tb_compute_core.sv` is the M2 deliverable and
  exercises the same Sobel-x kernel as one of its two test vectors.

## Notes for graders

* Both PASS lines (`tb_compute_core: PASS`, `tb_interface: PASS`) are present
  in the committed `sim/*_run.log` files.
* `waveform.png` shows the T1 window: clk, rst, in_valid, pixel, weight, count
  (0..27), and the signed 32-bit accumulator. The shaded red band marks the
  cycle in which `done` is asserted; the final accumulator value (`acc = 24`)
  is annotated on the right edge.
* The `unique case` warnings emitted by Icarus when compiling `interface.sv`
  are harmless — Icarus 12 ignores `unique` qualifiers but still compiles the
  case statement correctly. Synthesis tools (Vivado / Yosys) honor the
  qualifier and the design has been written to fall through to a default
  state for safety regardless.
