# M4 — Full-Layer INT8 Conv2D Accelerator (ECE 410/510 HW4AI Spring 2026)

This folder contains the complete M4 deliverable package for the INT8 2D Convolution
Accelerator: 64x64x3 to 64x64x16.

## File Catalog

| File | Description | Checklist |
|------|-------------|-----------|
| rtl/ | 8 RTL source files | §2 |
| tb/tb_top.sv | Final testbench | §2 |
| sim/final_run.log | Verilator PASS log, 4096/4096 beats | §2 |
| sim/final_waveform.png | GTKWave waveform from real VCD | §2 |
| synth/config.json | OpenLane 2.3.10 config | §3 |
| synth/openlane_run.log | Real OpenLane flow log | §3 |
| synth/timing_report.txt | Post-PnR STA results | §3 |
| synth/area_report.txt | 67785 cells, 958252 um2 | §3 |
| synth/power_report.txt | 81.04 mW total | §3 |
| bench/benchmark.md | Throughput, speedup, energy comparison | §4 |
| bench/benchmark_data.csv | Raw measurement data | §4 |
| bench/roofline_final.png | Final roofline with measured M4 point | §4 |
| report/design_justification.pdf | 9-section report, 3271 words | §5 |
| report/figures/ | Figures referenced in report | §5 |

## Key Results
- Simulation: PASS, 4096/4096 beats, TLAST=1
- Area: 958,252 um2 (67,785 cells)
- Power: 81.04 mW
- DRC: 0 violations
- Energy efficiency: 171x less than CPU baseline
