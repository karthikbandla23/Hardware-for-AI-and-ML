# M3 Plan — crossbar_mac Synthesis (Option B Fallback)

## Synthesis Attempt on Actual Project Core

I will attempt synthesis on my actual project compute core by **May 21, 2026** (3 days before M3 due date), leaving time to iterate.

## What I Expect to Be Different

Compared to the 4×4 crossbar_mac fallback, my actual project core is likely to differ in three ways. First, **size** will be larger if the core operates on larger matrices or higher precision than 8-bit — the 4×4 design produced 747 cells at 7,967 µm²; a larger core could easily be 5–10× that. Second, the **critical path location** will likely shift from the MUX-adder weight-selection tree to the accumulator or activation function logic, depending on the architecture. Third, if the project uses **lower precision** (e.g., 4-bit weights) the combinational depth should be shallower and slow-corner violations may be fewer.

## Lessons Applied from Fallback Exercise

The key lesson is that combinational dot-product logic fails the slow corner at 100 MHz on sky130A — the −2.416 ns WNS at `ss_100C_1v60` came directly from the unregistered accumulation chain. For M3, I will add a pipeline register at the mid-point of the MAC tree to cut the critical path depth, and I will provide a proper SDC file with input arrival times to get accurate timing closure instead of relying on the generic fallback SDC.
