# Remaining Tasks Before M4
**Project:** INT8 2D Convolution Accelerator (YOLO-style Detection Layer)
**Course:** ECE 410/510 — HW4AI, Spring 2026

---

## Change 1 — `interface.sv`: Replace the single `compute_core` instantiation with 16 parallel instances

Currently at line 214 in `interface.sv`, there is one `compute_core` instance:
```systemverilog
compute_core #(...) u_core (
    .pixel (pixel_in),
    .weight(weight_in),
    ...
);
```
Change this to a `generate` loop of 16 instances, each receiving the same shared
`pixel_in` but a different `weight_in` slice from a 16×27-byte weight register file.
This directly raises throughput from **200 MFLOP/s → 3,200 MFLOP/s** (16×), closing
the entire gap to the projected roofline ceiling.

---

## Change 2 — `interface.sv`: Widen `s_axis_tdata` from 16-bit to 272-bit to feed all 16 MACs per cycle

Currently `s_axis_tdata` is 16 bits — 8-bit pixel + 8-bit weight for one MAC:
```systemverilog
input logic [15:0] s_axis_tdata,
```
To keep all 16 MAC units active every cycle, change to:
```systemverilog
input logic [16*8-1:0] s_axis_tdata,  // 16 weights packed, 1 shared pixel
```
or use a separate AXI4-Stream weight-load phase before inference so weights are
pre-loaded into the register file and only the pixel stream (8-bit) is needed
per cycle during computation. Without this change, only 1 of the 16 cores
receives valid data per beat and the 16× parallelism is wasted.

---

## Change 3 — `compute_core.sv`: Replace the flat sequential accumulator with a 5-stage pipelined adder tree

Currently the accumulator adds one product per cycle over 27 cycles:
```systemverilog
out <= out + product_ext;  // line 102 — flat chain, 27 cycles latency
```
Replace with a depth-5 adder tree that reduces 27 products in 5 pipeline stages
(27→14→7→4→2→1). This reduces the critical-path adder depth from a 27-deep
chain to a single level per stage, allowing the design to meet timing closure
above 100 MHz on the Zynq-7020 when all 16 instances are active simultaneously.
Without this change, the 32-bit adder chain will be the critical path and
synthesis will fail to meet the 10 ns clock period constraint.
