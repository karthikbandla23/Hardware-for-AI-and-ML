import torch
import sys

# Detect GPU
if not torch.cuda.is_available():
    print("No CUDA GPU found. Exiting.")
    sys.exit(1)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")
print(f"GPU Name: {torch.cuda.get_device_name(0)}")

# Define network: 4 -> 5 (ReLU) -> 1 (linear)
model = torch.nn.Sequential(
    torch.nn.Linear(4, 5),
    torch.nn.ReLU(),
    torch.nn.Linear(5, 1)
)

# Move model to GPU
model.to(device)
print(f"Model device: {next(model.parameters()).device}")

# Generate random input batch [16, 4] and move to GPU
x = torch.randn(16, 4).to(device)
print(f"Input shape: {x.shape}")
print(f"Input device: {x.device}")

# Forward pass
output = model(x)
print(f"Output shape: {output.shape}")
print(f"Output device: {output.device}")
