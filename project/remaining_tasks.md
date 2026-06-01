# Remaining Tasks Before M4
**Project:** INT8 2D Convolution Accelerator (YOLO-style Detection Layer)
**Course:** ECE 410/510 — HW4AI, Spring 2026

---

## Change 1 — In `compute_core.sv` line 107: change `count == K_TOTAL - 1` to `count == K_TOTAL` to fix the premature `done` assertion that drops the 27th MAC result one cycle early

Current:
```systemverilog
if (!done && count == CNT_WIDTH'(K_TOTAL - 1)) begin
    done <= 1'b1;
end
```
`done` fires at `count = 26` but the 27th product (`count = 27`) has already been added to `out` in the same cycle via the `else` branch at line 102. The off-by-one means `done` and the final accumulated value are misaligned by one cycle, forcing the downstream `interface.sv` to latch `core_out` one cycle too early before the 27th MAC is fully committed.

Change to:
```systemverilog
if (!done && count == CNT_WIDTH'(K_TOTAL)) begin
    done <= 1'b1;
end
```

---

## Change 2 — In `interface.sv`: remove `armed_q <= 1'b0` on `core_done_w` to eliminate the mandatory idle gap between back-to-back convolution windows

Current:
```systemverilog
if (core_done_w) begin
    reg_result       <= core_out;
    result_pending_q <= 1'b1;
    core_done        <= 1'b1;
    core_busy        <= 1'b0;
    armed_q          <= 1'b0;  // forces pipeline to stall — requires new START write
end
```
Deasserting `armed_q` on every `core_done_w` stalls the MAC pipeline after every 27-MAC window and requires the host CPU to write START again via AXI4-Lite before the next window can begin. Across 65,536 windows per inference this adds tens of thousands of idle cycles. Remove `armed_q <= 1'b0` so the pipeline stays armed and accepts the next window immediately:
```systemverilog
if (core_done_w) begin
    reg_result       <= core_out;
    result_pending_q <= 1'b1;
    core_done        <= 1'b1;
    core_busy        <= 1'b0;
    // armed_q stays high — back-to-back windows stream without host intervention
end
```

---

## Change 3 — In `compute_core.sv` lines 97-100: remove the reset-accumulator branch on `done` to eliminate the one wasted cycle at the start of every new window

Current:
```systemverilog
if (done || count == K_TOTAL) begin
    out   <= product_ext;   // replaces accumulator — wastes the first MAC of new window
    count <= CNT_WIDTH'(1);
end else begin
    out   <= out + product_ext;
    count <= count + CNT_WIDTH'(1);
end
```
When `done` is high the first product of the new window replaces `out` instead of being added to a cleared accumulator. This means the accumulator is never explicitly zeroed — it relies on the replace-branch to reset state. Change to explicitly clear `out` on `done` and always accumulate:
```systemverilog
if (done) begin
    out   <= '0;            // explicit clear on window boundary
    count <= '0;
end else if (in_valid) begin
    out   <= out + product_ext;
    count <= count + CNT_WIDTH'(1);
end
```
This removes the implicit reset-via-replace behaviour, makes the accumulator reset explicit and one cycle earlier, and allows the first MAC of the new window to accumulate cleanly into a zeroed register without a special-case branch.
