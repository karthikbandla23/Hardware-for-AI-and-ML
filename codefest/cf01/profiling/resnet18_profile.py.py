import torch
import torchvision.models as models
from torchinfo import summary
import os

model = models.resnet18()

os.makedirs("codefest/cf01/profiling", exist_ok=True)

model_summary = summary(
    model,
    input_size=(1, 3, 224, 224),
    col_names=("input_size", "output_size", "num_params", "mult_adds"),
    depth=3
)

file_path = "codefest/cf01/profiling/resnet18_profile.txt"

# ✅ FIX HERE
with open(file_path, "w", encoding="utf-8") as f:
    f.write(str(model_summary))

print("✅ Saved successfully!")
