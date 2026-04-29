"""
conv2d_core testbench stub.
Drives reset and applies one representative 3x3 convolution.

Example: pixel patch * Sobel-x kernel
    pixel  = [[1, 2, 3],          weight = [[-1, 0, 1],
              [4, 5, 6],                    [-2, 0, 2],
              [7, 8, 9]]                    [-1, 0, 1]]

    expected = sum( pixel[i,j] * weight[i,j] )
             = (1*-1 + 2*0 + 3*1) + (4*-2 + 5*0 + 6*2) + (7*-1 + 8*0 + 9*1)
             = (2)             + (4)             + (2)
             = 8
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def test_conv2d_core_basic(dut):
    """One 3x3 convolution: pixel patch * Sobel-x kernel = 8."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Reset
    dut.rst.value = 1
    dut.in_valid.value = 0
    dut.pixel.value = 0
    dut.weight.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.rst.value = 0

    # Stimulus: stream the 9 (pixel, weight) pairs
    pixels  = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    weights = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
    expected = sum(p * w for p, w in zip(pixels, weights))   # = 8

    dut.in_valid.value = 1
    for p, w in zip(pixels, weights):
        dut.pixel.value = p
        dut.weight.value = w
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    dut.in_valid.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    got = dut.out.value.to_signed()
    dut._log.info(f"conv result = {got}, expected {expected}, done = {int(dut.done.value)}")
    assert got == expected, f"convolution mismatch: got {got}, expected {expected}"
    assert int(dut.done.value) == 1, "done should be asserted after K*K MACs"
    dut._log.info("test_conv2d_core_basic PASSED")
