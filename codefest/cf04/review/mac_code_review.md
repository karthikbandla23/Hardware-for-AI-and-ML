# MAC Code Review — CF04 CLLM

**Course:** ECE 410/510 — HW4AI, Spring 2026
**Codefest:** 4
**Module under review:** `mac` (8-bit signed multiply-accumulate)

---

## LLM models used

| File | LLM | Model version |
|------|-----|----------------|
| `mac_llm_A.v` | ChatGPT | 5
| `mac_llm_B.v` | Claude  | Opus 4.7

---

## Specification recap

- Module name: `mac`
- Inputs: `clk` (1-bit), `rst` (1-bit, active-high synchronous), `a` (8-bit signed), `b` (8-bit signed)
- Output: `out` (32-bit signed accumulator)
- Behavior: on rising edge — if `rst`, set `out=0`; else `out <= out + a*b`.
- Constraints: synthesizable SystemVerilog only, `always_ff`, no `initial`, no `$display`, no `#` delays.

---

## Compile results

Both files compile cleanly with `iverilog -g2012 -Wall`. The only message is the unrelated timescale warning emitted by the testbench:

```
warning: Some design elements have no explicit time unit and/or
       : time precision. This may cause confusing timing results.
```

This is a testbench-side issue (no `timescale` propagated into the DUT) and not a bug in either DUT. No errors.

---

## Simulation results

Stimulus per spec: `[a=3, b=4]` for 3 cycles, assert `rst`, then `[a=−5, b=2]` for 2 cycles. Expected sequence: **12, 24, 36, 0, −10, −20**.

### `mac_llm_A.v` — **FAIL**

```
after reset    : out = 0   (expect 0)
cycle 1 (3*4)  : out = 12  (expect 12)
cycle 2 (3*4)  : out = 24  (expect 24)
cycle 3 (3*4)  : out = 36  (expect 36)
after rst pulse: out = 0   (expect 0)
cycle 4 (-5*2) : out = 502 (expect -10)   <-- WRONG
cycle 5 (-5*2) : out = 1004 (expect -20)  <-- WRONG
RESULT: FAIL  (final out = 1004, expected -20)
```

### `mac_llm_B.v` — PASS (functional), but with concerns

```
after reset    : out = 0   (expect 0)
cycle 1 (3*4)  : out = 12  (expect 12)
cycle 2 (3*4)  : out = 24  (expect 24)
cycle 3 (3*4)  : out = 36  (expect 36)
after rst pulse: out = 0   (expect 0)
cycle 4 (-5*2) : out = -10 (expect -10)
cycle 5 (-5*2) : out = -20 (expect -20)
RESULT: PASS
```

### `mac_correct.v` — PASS

Same output as `mac_llm_B.v`, with explicit defensive sign extension (see Issue 2).

---

## Issues found

### Issue 1 — `mac_llm_A.v`: missing `signed` declarations (sign-extension bug)

**Offending lines (`mac_llm_A.v`, lines 7–10 and 16):**

```verilog
input             clk,
input             rst,
input      [7:0]  a,
input      [7:0]  b,
output reg [31:0] out
...
out <= out + (a * b);
```

**Why it is wrong:**
The spec says `a` and `b` are **8-bit signed**, but no operand in this module is declared `signed`. In Verilog, an arithmetic expression is treated as signed only if **every** operand is signed. Here `a * b` is computed as an unsigned 8×8 multiply, so when `a = -5` (binary `8'b1111_1011` = unsigned 251) and `b = 2`, the product is `502` instead of `−10`. The accumulator is then incremented by 502 each cycle, so the final value after two cycles is **1004 instead of −20** — confirmed in the simulation log above. This is the classic "sign-extension error" failure mode flagged in the assignment's failure-mode table.

**Corrected version:**

```verilog
input  logic signed [7:0]  a,
input  logic signed [7:0]  b,
output logic signed [31:0] out
...
out <= out + (a * b);   // now signed * signed -> signed product
```

### Issue 2 — `mac_llm_A.v`: `always @(posedge clk)` instead of `always_ff`

**Offending line (`mac_llm_A.v`, line 12):**

```verilog
always @(posedge clk) begin
```

**Why it is wrong:**
The spec explicitly requires `always_ff`. Plain `always @(posedge clk)` is legal Verilog-2001 but does not give the synthesis tool the designer-intent assertion that this block must infer flip-flops only — `always_ff` causes the tool to error out if combinational paths leak in. Using the wrong process type is the second failure mode listed in the assignment.

**Corrected version:**

```verilog
always_ff @(posedge clk) begin
```

### Issue 3 — `mac_llm_B.v`: implicit (rather than explicit) sign extension of the 16-bit product into the 32-bit accumulator

**Offending lines (`mac_llm_B.v`, lines 11 and 18):**

```verilog
logic signed [15:0] product;
...
out <= out + product;
```

**Why it is wrong (or, more precisely, *fragile*):**
The 8×8 signed multiply produces a 16-bit signed `product`, which is then added to a 32-bit signed `out`. This works **only** because every operand in the addition is signed — the simulator implicitly sign-extends the 16-bit value to 32 bits. If a future maintainer drops the `signed` keyword on `product` (or on `out`), the addition silently becomes a zero-extended unsigned operation, and negative products will start adding huge positive numbers to the accumulator — exactly the bug seen in `mac_llm_A.v`, but harder to spot because the basic test still appears to work for a while. The assignment's failure-mode table calls this out directly: "accumulator width mismatch — accumulating 16-bit product into 32-bit register without sign extension".

**Corrected version (defensive, explicit):**

```verilog
logic signed [15:0] product;
logic signed [31:0] product_ext;

assign product     = a * b;
assign product_ext = {{16{product[15]}}, product};   // explicit sign extension
...
out <= out + product_ext;
```

This is what `mac_correct.v` does.

---

## Corrected file

See `codefest/cf04/hdl/mac_correct.v`. Summary of changes vs. the LLM outputs:

- All signed operands declared `logic signed [...]`.
- `always_ff` (per spec).
- 16-bit product **explicitly** sign-extended to 32 bits before being added to the accumulator.
- Synchronous active-high reset writes `32'sd0`.

### Compile and simulation

```
$ iverilog -g2012 -o mac_sim mac_correct.v mac_tb.v
$ vvp mac_sim
after reset    : out = 0 (expect 0)
cycle 1 (3*4)  : out = 12 (expect 12)
cycle 2 (3*4)  : out = 24 (expect 24)
cycle 3 (3*4)  : out = 36 (expect 36)
after rst pulse: out = 0 (expect 0)
cycle 4 (-5*2) : out = -10 (expect -10)
cycle 5 (-5*2) : out = -20 (expect -20)
RESULT: PASS
```

### Yosys synthesis

```
$ yosys -p 'read_verilog -sv mac_correct.v; synth; stat'
...
=== mac ===
Number of wires:               1039
Number of wire bits:           1301
Number of cells:               1091
  $_SDFF_PP0_                    32   <-- 32 sync DFFs with active-high reset (correct: 32-bit accumulator)
  $_XOR_                        273   <-- adder/multiplier logic
  $_AND_                         61
  ...
```

32 synchronous DFFs with active-high reset are inferred — exactly one per accumulator bit — confirming `always_ff` + synchronous reset synthesized correctly. Full log committed as `yosys_correct.log`.

---

## Failure-mode summary

| Failure mode (from assignment)             | Found in   | Fixed in `mac_correct.v` |
|--------------------------------------------|------------|--------------------------|
| Wrong process type (`always` vs `always_ff`) | `mac_llm_A.v` | yes |
| Sign-extension error                       | `mac_llm_A.v` | yes |
| Accumulator width mismatch (implicit ext.) | `mac_llm_B.v` | yes (explicit extension) |
| Non-synthesizable constructs               | none       | n/a |
| Reset polarity error                       | none       | n/a |
| Missing port direction                     | none       | n/a |
