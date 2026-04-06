## ResNet-18 Analysis

### Top 5 MAC-Intensive Layers

| Layer Name    | MACs         | Parameters |
|---------------|-------------|------------|
| Conv2d (1-1)  | 118,013,952 | 9,408      |
| Conv2d (3-1)  | 115,605,504 | 36,864     |
| Conv2d (3-4)  | 115,605,504 | 36,864     |
| Conv2d (3-7)  | 115,605,504 | 36,864     |
| Conv2d (3-10) | 115,605,504 | 36,864     |

### Arithmetic Intensity (Most MAC-Intensive Layer)

**Selected Layer:** Conv2d (1-1) — 7×7 stem convolution  
(Input: 3×224×224 → Output: 64×112×112)

FLOPs = 2 × 118,013,952 = 236,027,904  

Weight Memory = 9,408 × 4 = 37,632 bytes  

**Activation Memory:**
- Input = 3 × 224 × 224 × 4 = 602,112 bytes  
- Output = 64 × 112 × 112 × 4 = 3,211,264 bytes  
- Total Activation = 3,813,376 bytes  

**Total Memory:**
- 37,632 + 3,813,376 = 3,851,008 bytes  

**Arithmetic Intensity:**
AI = 236,027,904 / 3,851,008 ≈ 61.3 FLOP/byte
