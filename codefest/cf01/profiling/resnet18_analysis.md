# ResNet-18 Analysis

## Top 5 MAC-Intensive Layers

| Layer Name | MACs | Parameters |
|-----------|------|-----------|
| Conv2d (3-1) | 115,605,504 | 36,864 |
| Conv2d (3-4) | 115,605,504 | 36,864 |
| Conv2d (3-7) | 115,605,504 | 36,864 |
| Conv2d (3-10) | 115,605,504 | 36,864 |
| Conv2d (3-16) | 115,605,504 | 147,456 |

---

## Arithmetic Intensity (Most MAC-Intensive Layer)

Selected Layer: Conv2d (3-1)

MACs = 115,605,504  
FLOPs = 2 × MACs = 231,211,008  

Weight Memory:  
36,864 × 4 = 147,456 bytes  

Activation Memory:  
Input = 64 × 56 × 56 × 4 = 802,816 bytes  
Output = 64 × 56 × 56 × 4 = 802,816 bytes  
Total Activation = 1,605,632 bytes  

Total Memory:  
147,456 + 1,605,632 = 1,753,088 bytes  

Arithmetic Intensity:  
AI = 231,211,008 / 1,753,088 ≈ 132 FLOP/byte
