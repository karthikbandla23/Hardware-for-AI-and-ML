"""
cocotb testbench for mac_correct.v
- test_mac_basic: spec stimulus from CF04
- test_mac_overflow: drive accumulator near 2^31-1 to observe wrap-vs-saturate
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def test_mac_basic(dut):
    """Spec stimulus: a=3, b=4 for 3 cycles, reset, a=-5, b=2 for 2 cycles."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Initial reset cycle
    dut.rst.value = 1
    dut.a.value = 0
    dut.b.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")  # let DUT settle, sample after edge
    dut.rst.value = 0

    # Phase 1: a=3, b=4 -> expect 12, 24, 36 on three successive edges
    dut.a.value = 3
    dut.b.value = 4
    for expected in [12, 24, 36]:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        got = dut.out.value.to_signed()
        assert got == expected, f"basic phase1: got {got}, expected {expected}"

    # Reset pulse
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    got = dut.out.value.to_signed()
    assert got == 0, f"after reset: got {got}, expected 0"
    dut.rst.value = 0

    # Phase 2: a=-5, b=2 -> expect -10, -20
    dut.a.value = -5
    dut.b.value = 2
    for expected in [-10, -20]:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        got = dut.out.value.to_signed()
        assert got == expected, f"basic phase2: got {got}, expected {expected}"

    dut._log.info("test_mac_basic PASSED")


@cocotb.test()
async def test_mac_overflow(dut):
    """
    Drive the accumulator close to 2^31 - 1 = 2,147,483,647 and observe.
    Max positive product is 127 * 127 = 16,129 per cycle.
    n * 16129 ~= 2,147,483,647  ->  n ~= 133,143 cycles.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst.value = 1
    dut.a.value = 0
    dut.b.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.rst.value = 0

    INT32_MAX = 2**31 - 1
    INT32_MIN = -(2**31)

    dut.a.value = 127
    dut.b.value = 127
    n_cycles = 133_200
    expected = 0
    wrapped = False
    for i in range(n_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        expected += 127 * 127
        actual = dut.out.value.to_signed()

        if not wrapped and actual < 0:
            wrapped = True
            dut._log.info(
                f"WRAP observed at cycle {i+1}: out = {actual} "
                f"(unbounded expected = {expected})"
            )

    final = dut.out.value.to_signed()
    dut._log.info(f"final out after {n_cycles} cycles: {final}")
    dut._log.info(f"unbounded sum would be:           {expected}")

    # Document behavior: design WRAPS (does not saturate). Accumulator is a plain
    # 32-bit signed register with no clamping logic, so on overflow it rolls over
    # in two's-complement style.
    assert wrapped, "expected accumulator to wrap; it did not"
    assert INT32_MIN <= final <= INT32_MAX, \
        f"final value {final} outside int32 range -- simulator bug?"

    dut._log.info("test_mac_overflow PASSED -- behavior: WRAPS (two's-complement rollover)")
