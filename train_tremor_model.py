"""
train_tremor_model.py
─────────────────────
Trains a 1D CNN on the Parkinson's Disease Tremor Dataset and exports a
CoreML model (TremorCoreMLClassifier.mlmodel) for use in TremorMitigationApp.

Usage
─────
1. Clone the dataset:
       git clone https://github.com/jiehu01/Parkinson-s-Disease-Tremor-Dataset

2. Install dependencies:
       pip install torch numpy scikit-learn coremltools

3. Run:
       python train_tremor_model.py --dataset /path/to/Parkinson-s-Disease-Tremor-Dataset

4. Drag the output TremorCoreMLClassifier.mlmodel into your Xcode project
   (add to the TremorMitigation target).

Dataset format
──────────────
Each dataset folder contains pairs:
    {ID}-X.npy   shape [N, 128, 3]   — 128 time steps × 3 accel axes at 50 Hz
    {ID}-Y.npy   shape [N]            — labels 0 (no tremor) / 1-3 (tremor severity)

Model I/O
─────────
Input  : imuWindow   float32  shape (1, 128, 3)
Output : tremorProbability  float32  shape (1,)   — probability tremor is present
"""

import argparse
import pathlib
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset, WeightedRandomSampler
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import coremltools as ct

# ─────────────────────────────────────────
# 1.  Load dataset
# ─────────────────────────────────────────

DATASET_DIRS = ["Tim-Tremor", "PdAssist", "IMU-Wild", "PD-BioStamp"]

def load_dataset(root: pathlib.Path):
    """
    Walk all four dataset sub-directories, load every *-X.npy / *-Y.npy pair,
    and return (X, y) with:
        X  float32  [total_windows, 128, 3]
        y  int64    [total_windows]   — binary: 0 = no tremor, 1 = tremor
    """
    all_X, all_y = [], []

    for sub in DATASET_DIRS:
        folder = root / sub
        if not folder.exists():
            print(f"  [skip] {folder} not found")
            continue

        x_files = sorted(folder.glob("*-X.npy"))
        print(f"  {sub}: {len(x_files)} segment files")

        for xf in x_files:
            yf = xf.with_name(xf.name.replace("-X.npy", "-Y.npy"))
            if not yf.exists():
                continue

            X = np.load(xf)   # [N, 128, 3]  (some files may be [N, 3, 128])
            y = np.load(yf)   # [N]

            # Normalise shape to [N, 128, 3]
            if X.ndim == 3 and X.shape[1] == 3 and X.shape[2] == 128:
                X = X.transpose(0, 2, 1)   # [N, 3, 128] → [N, 128, 3]
            if X.ndim != 3 or X.shape[1] != 128 or X.shape[2] != 3:
                print(f"    [skip] unexpected shape {X.shape} in {xf.name}")
                continue
            if len(y) != len(X):
                print(f"    [skip] X/Y length mismatch in {xf.name}")
                continue

            all_X.append(X.astype(np.float32))
            # Binarise: label 0 → no tremor (0), labels 1/2/3 → tremor (1)
            all_y.append((y > 0).astype(np.int64))

    if not all_X:
        raise RuntimeError(
            "No data loaded. Check --dataset path and that the repo contains "
            "Tim-Tremor/, PdAssist/, IMU-Wild/, PD-BioStamp/ subdirectories."
        )

    X = np.concatenate(all_X, axis=0)
    y = np.concatenate(all_y, axis=0)
    print(f"\nTotal windows : {len(X)}")
    print(f"Tremor (1)    : {y.sum()}  ({100*y.mean():.1f}%)")
    print(f"No tremor (0) : {(y==0).sum()}  ({100*(1-y.mean()):.1f}%)")
    return X, y


# ─────────────────────────────────────────
# 2.  Normalise
# ─────────────────────────────────────────

def normalise(X_train, X_val, X_test):
    """Per-channel z-score normalisation fit on training data only."""
    # Flatten to [N*128, 3] for scaler, then reshape back
    N_tr, T, C = X_train.shape
    scaler = StandardScaler()
    X_train_flat = X_train.reshape(-1, C)
    scaler.fit(X_train_flat)

    def transform(X):
        n = X.shape[0]
        return scaler.transform(X.reshape(-1, C)).reshape(n, T, C).astype(np.float32)

    return transform(X_train), transform(X_val), transform(X_test), scaler


# ─────────────────────────────────────────
# 3.  Model
# ─────────────────────────────────────────

class TremorCNN(nn.Module):
    """
    Lightweight 1-D CNN for binary tremor classification.

    Input : (batch, 128, 3)   — time × channels
    Output: (batch, 1)        — tremor probability (after sigmoid)

    Architecture:
        Three Conv1d blocks with increasing depth capture local temporal
        patterns at multiple scales (7-, 5-, 3-sample receptive fields).
        Global average pooling collapses the time dimension, and two FC
        layers produce the final probability.
    """
    def __init__(self):
        super().__init__()
        # Conv layers expect (batch, channels, time) — we permute in forward()
        self.block1 = nn.Sequential(
            nn.Conv1d(3, 32, kernel_size=7, padding=3),
            nn.BatchNorm1d(32),
            nn.ReLU(),
            nn.MaxPool1d(2),          # 128 → 64
        )
        self.block2 = nn.Sequential(
            nn.Conv1d(32, 64, kernel_size=5, padding=2),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.MaxPool1d(2),          # 64 → 32
        )
        self.block3 = nn.Sequential(
            nn.Conv1d(64, 128, kernel_size=3, padding=1),
            nn.BatchNorm1d(128),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(1),  # 32 → 1  (global avg pool)
        )
        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(64, 1),
            nn.Sigmoid(),
        )

    def forward(self, x):
        # x: (batch, 128, 3) → (batch, 3, 128)
        x = x.permute(0, 2, 1)
        x = self.block1(x)
        x = self.block2(x)
        x = self.block3(x)
        return self.head(x)


# ─────────────────────────────────────────
# 4.  Train
# ─────────────────────────────────────────

def make_loader(X, y, batch_size=64, oversample=False):
    X_t = torch.from_numpy(X)
    y_t = torch.from_numpy(y).float()
    ds  = TensorDataset(X_t, y_t)

    if oversample:
        # Weighted sampler to counter class imbalance
        class_counts = np.bincount(y)
        weights      = 1.0 / class_counts[y]
        sampler      = WeightedRandomSampler(weights, len(weights), replacement=True)
        return DataLoader(ds, batch_size=batch_size, sampler=sampler)

    return DataLoader(ds, batch_size=batch_size, shuffle=False)


def train(model, loader_tr, loader_val, epochs=30, lr=1e-3, device="cpu"):
    opt       = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    # Pos weight to handle remaining imbalance after oversampling
    pos_weight = torch.tensor([3.0], device=device)
    criterion  = nn.BCELoss()            # model already applies sigmoid

    best_val_loss = float("inf")
    best_state    = None

    for epoch in range(1, epochs + 1):
        # ── train ──
        model.train()
        tr_loss = 0.0
        for xb, yb in loader_tr:
            xb, yb = xb.to(device), yb.to(device)
            opt.zero_grad()
            pred = model(xb).squeeze(1)
            loss = criterion(pred, yb)
            loss.backward()
            opt.step()
            tr_loss += loss.item() * len(xb)
        tr_loss /= len(loader_tr.dataset)

        # ── validate ──
        model.eval()
        val_loss, correct, total = 0.0, 0, 0
        with torch.no_grad():
            for xb, yb in loader_val:
                xb, yb = xb.to(device), yb.to(device)
                pred  = model(xb).squeeze(1)
                val_loss += criterion(pred, yb).item() * len(xb)
                correct  += ((pred >= 0.5) == yb.bool()).sum().item()
                total    += len(xb)
        val_loss /= len(loader_val.dataset)
        val_acc   = 100 * correct / total

        scheduler.step()

        if val_loss < best_val_loss:
            best_val_loss = val_loss
            best_state    = {k: v.clone() for k, v in model.state_dict().items()}

        if epoch % 5 == 0 or epoch == 1:
            print(f"  Epoch {epoch:3d}/{epochs}  "
                  f"train_loss={tr_loss:.4f}  "
                  f"val_loss={val_loss:.4f}  "
                  f"val_acc={val_acc:.1f}%")

    model.load_state_dict(best_state)
    return model


# ─────────────────────────────────────────
# 5.  Evaluate
# ─────────────────────────────────────────

def evaluate(model, loader, device="cpu"):
    model.eval()
    all_pred, all_true = [], []
    with torch.no_grad():
        for xb, yb in loader:
            pred = model(xb.to(device)).squeeze(1).cpu().numpy()
            all_pred.append(pred)
            all_true.append(yb.numpy())
    pred = np.concatenate(all_pred)
    true = np.concatenate(all_true)

    binary_pred = (pred >= 0.5).astype(int)
    acc       = (binary_pred == true).mean()
    tp        = ((binary_pred == 1) & (true == 1)).sum()
    fp        = ((binary_pred == 1) & (true == 0)).sum()
    fn        = ((binary_pred == 0) & (true == 1)).sum()
    precision = tp / (tp + fp + 1e-8)
    recall    = tp / (tp + fn + 1e-8)
    f1        = 2 * precision * recall / (precision + recall + 1e-8)

    print(f"\nTest results:")
    print(f"  Accuracy  : {100*acc:.1f}%")
    print(f"  Precision : {100*precision:.1f}%")
    print(f"  Recall    : {100*recall:.1f}%")
    print(f"  F1        : {f1:.3f}")


# ─────────────────────────────────────────
# 6.  Export to CoreML
# ─────────────────────────────────────────

def export_coreml(model, output_path: pathlib.Path, scaler):
    """
    Export the trained PyTorch model to CoreML (.mlmodel).

    The Swift app feeds a window of shape (1, 128, 3) as a float32 MLMultiArray.
    The model returns tremorProbability as a float32 scalar.

    Scaler mean/std are embedded as CoreML preprocessing so the app doesn't
    need to replicate normalisation logic.
    """
    model.eval()
    example_input = torch.zeros(1, 128, 3)

    traced = torch.jit.trace(model, example_input)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="imuWindow",
                shape=(1, 128, 3),
                dtype=np.float32,
            )
        ],
        outputs=[
            ct.TensorType(name="tremorProbability", dtype=np.float32)
        ],
        minimum_deployment_target=ct.target.watchOS7,
    )

    # Store normalisation parameters as model metadata so we can reconstruct
    # them in Swift if needed (the model itself sees normalised input)
    mlmodel.short_description = "Binary tremor classifier for Parkinson's Disease"
    mlmodel.input_description["imuWindow"] = (
        "128-sample window of 3-axis accelerometer data at 50 Hz, "
        "z-score normalised per channel. Shape: (1, 128, 3)."
    )
    mlmodel.output_description["tremorProbability"] = (
        "Probability that the window contains tremor (0 = no tremor, 1 = tremor)."
    )
    # Embed scaler params as user-defined metadata
    mlmodel.user_defined_metadata["scaler_mean"] = ",".join(
        str(v) for v in scaler.mean_.tolist()
    )
    mlmodel.user_defined_metadata["scaler_scale"] = ",".join(
        str(v) for v in scaler.scale_.tolist()
    )

    mlmodel.save(str(output_path))
    print(f"\nSaved CoreML model → {output_path}")
    print("Next steps:")
    print("  1. Drag TremorCoreMLClassifier.mlmodel into Xcode")
    print("  2. Add it to the TremorMitigation target")
    print("  3. Uncomment the CoreML lines in TremorClassifier.swift")


# ─────────────────────────────────────────
# 7.  Main
# ─────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset",
        required=True,
        help="Path to the cloned Parkinson-s-Disease-Tremor-Dataset directory",
    )
    parser.add_argument("--epochs",     type=int,   default=30)
    parser.add_argument("--batch_size", type=int,   default=64)
    parser.add_argument("--lr",         type=float, default=1e-3)
    parser.add_argument("--output",     default="TremorCoreMLClassifier.mlmodel")
    args = parser.parse_args()

    device = (
        "mps"  if torch.backends.mps.is_available()  # Apple Silicon
        else "cuda" if torch.cuda.is_available()
        else "cpu"
    )
    print(f"Device: {device}\n")

    # 1. Load
    print("Loading dataset...")
    root = pathlib.Path(args.dataset)
    X, y = load_dataset(root)

    # 2. Split  (stratified: preserve tremor/no-tremor ratio in each split)
    X_train, X_tmp, y_train, y_tmp = train_test_split(
        X, y, test_size=0.30, random_state=42, stratify=y
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_tmp, y_tmp, test_size=0.50, random_state=42, stratify=y_tmp
    )
    print(f"\nSplit → train:{len(X_train)}  val:{len(X_val)}  test:{len(X_test)}")

    # 3. Normalise
    X_train, X_val, X_test, scaler = normalise(X_train, X_val, X_test)

    # 4. DataLoaders
    loader_tr  = make_loader(X_train, y_train, args.batch_size, oversample=True)
    loader_val = make_loader(X_val,   y_val,   args.batch_size)
    loader_te  = make_loader(X_test,  y_test,  args.batch_size)

    # 5. Train
    print(f"\nTraining for {args.epochs} epochs...")
    model = TremorCNN().to(device)
    model = train(model, loader_tr, loader_val, args.epochs, args.lr, device)

    # 6. Evaluate
    evaluate(model.to("cpu"), loader_te, "cpu")

    # 7. Export
    output = pathlib.Path(args.output)
    export_coreml(model.to("cpu"), output, scaler)


if __name__ == "__main__":
    main()
