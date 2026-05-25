# CMAN – AER Bandwidth Analysis
## CF08 | ECE 510 | Spring 2026

---

### Task 1 – Mean Aggregate Spike Rate

The total spike rate across all neurons is just N times the per-neuron firing rate:

R = N × f = 1024 × 50 = **51,200 spikes/s**

---

### Task 2 – Mean AER Bandwidth

Each packet is 20 bits (10-bit address + 6-bit timestamp + 4-bit framing/parity), so:

B = R × 20 bits/spike = 51,200 × 20 = 1,024,000 bits/s

**B ≈ 1.024 Mbit/s**

---

### Task 3 – Interface Comparison

| Interface   | Max throughput  | Sustains 1.024 Mbit/s? |
|-------------|-----------------|------------------------|
| I²C         | 3.4 Mbit/s      | Yes                    |
| SPI         | 50 Mbit/s       | Yes                    |
| AXI4-Lite   | ~100 Mbit/s     | Yes                    |

All three can handle the mean rate. **I²C is the lowest-complexity choice** — two wires, no chip select lines, and 3.4 Mbit/s is more than enough headroom over the 1.024 Mbit/s mean.

---

### Task 4 – Burst Analysis

If 25% of neurons fire within a 1 ms window:

- Neurons firing: 0.25 × 1024 = 256
- Bits in the burst: 256 × 20 = 5,120 bits
- Peak bandwidth: 5,120 bits / 0.001 s = **5.12 Mbit/s**

Burst-to-mean ratio: 5.12 / 1.024 = **5:1**

I²C tops out at 3.4 Mbit/s, so it can't keep up with the 5.12 Mbit/s burst peak — **buffering is required**. The excess data that builds up during the 1 ms burst window is:

(5.12 − 3.4) Mbit/s × 0.001 s = 1,720 bits ≈ **215 bytes minimum buffer**

SPI and AXI4-Lite both exceed 5.12 Mbit/s, so they'd absorb the burst without needing a buffer.

---

### Task 5 – Frame-Based Comparison

A conventional readout samples all 1024 neurons every millisecond, 1 bit per neuron:

B_frame = 1024 bits/frame × 1000 frames/s = **1.024 Mbit/s**

AER-to-frame ratio at f = 50 Hz: 1.024 / 1.024 = **1:1**

To find the crossover firing rate, set the two bandwidths equal:

N × f_crossover × 20 = N × 1000

f_crossover = 1000 / 20 = **50 Hz**

This makes sense — at exactly 50 Hz mean firing rate, both schemes use the same bandwidth. **AER is worth using when mean firing rates stay below 50 Hz**, since sparser activity means fewer packets than the fixed frame cost; once activity climbs above that threshold, it's cheaper to just send frames.
