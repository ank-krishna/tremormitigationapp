# TremorCalm

**Real-time Parkinson's tremor detection and adaptive haptic mitigation for Apple Watch and iPhone.**

TremorCalm uses on-device machine learning and motion sensors to detect involuntary tremor in real time, then delivers precisely timed haptic stimulation synchronized to the user's tremor frequency — helping reduce tremor amplitude through sensory entrainment.

---

## Features

### Intelligent Tremor Detection
- 100 Hz accelerometer + gyroscope sampling via CoreMotion
- FFT-based spectral analysis targeting the 3–12 Hz Parkinson's tremor band
- CoreML classifier (1D CNN) trained on real clinical tremor data
- Automatic fallback to a hand-crafted heuristic if the ML model is unavailable

### Adaptive Haptic Stimulation
- Rhythmic haptic pulses locked to the detected tremor frequency
- Three stimulation modes: Vibration, Electrical, and Combined
- Adjustable intensity (Low / Medium / High) with real-time Digital Crown control on watchOS
- CoreHaptics on iOS, WatchKit haptics on watchOS

### Personalized Tremor Profiles
- Incrementally learns each user's unique tremor characteristics across sessions
- Exponential moving average (EMA) adaptation with persistent storage
- Profile calibration indicator — improves recommendations over 20+ observations
- Learned dominant frequency drives automatic haptic tuning

### Live Efficacy Tracking
- Measures tremor amplitude reduction during each session
- 10-second baseline capture before stimulation takes effect
- Real-time efficacy percentage displayed during the session
- Per-session history with completion status and reduction metrics

### HealthKit Integration
- Logs sessions as `HKWorkout` entries
- Records tremor episodes as `HKCategorySample` with severity, frequency, and efficacy metadata

### Safety System
- Maximum 60-minute session duration
- Enforced 5-minute rest periods between sessions
- Configurable daily session limit (default: 8)
- Auto-pause after 60 seconds of inactivity
- Emergency stop button

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       SwiftUI Views                         │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │   iOS    │  │   watchOS    │  │   Shared Components    │ │
│  │  Views   │  │    Views     │  │  (Onboarding, Settings)│ │
│  └────┬─────┘  └──────┬───────┘  └───────────┬────────────┘ │
├───────┴────────────────┴─────────────────────┴──────────────┤
│                   StimulationService                        │
│            (Central session controller)                     │
├──────────┬──────────────┬───────────────┬───────────────────┤
│  Tremor  │   Tremor     │   Adaptive    │    Tremor         │
│ Detector │  Classifier  │   Haptic      │    Filter         │
│ (FFT +   │  (CoreML /   │   Engine      │  (IIR notch +    │
│ CoreMo-  │  heuristic)  │  (platform-   │  jerk-based      │
│  tion)   │              │   specific)   │  intent detect)   │
├──────────┴──────────────┴───────────────┴───────────────────┤
│  TremorLearningEngine  │  HealthKitManager  │ SettingsManager│
│  (EMA profile learning)│  (Workout logging) │ (Persistence)  │
└─────────────────────────────────────────────────────────────┘
```

---

## ML Pipeline

### Dataset

Trained on the [Parkinson's Disease Tremor Dataset](https://github.com/jiehu01/Parkinson-s-Disease-Tremor-Dataset), which includes four clinical sub-datasets:

| Sub-dataset   | Source        |
|---------------|---------------|
| Tim-Tremor    | Clinical IMU  |
| PdAssist      | Clinical IMU  |
| IMU-Wild      | In-the-wild   |
| PD-BioStamp   | BioStamp nPoint sensors |

Data format: 128-sample windows at 50 Hz across 3 accelerometer axes, with labels binarized to tremor / no-tremor.

### Model Architecture — TremorCNN

```
Input (1, 128, 3) ── permute to (1, 3, 128)
        │
        ▼
  Conv1d(3→32, k=7) → BatchNorm → ReLU → MaxPool(2)     [128 → 64]
        │
        ▼
  Conv1d(32→64, k=5) → BatchNorm → ReLU → MaxPool(2)    [64 → 32]
        │
        ▼
  Conv1d(64→128, k=3) → BatchNorm → ReLU → AdaptiveAvgPool(1)
        │
        ▼
  Linear(128→64) → ReLU → Dropout(0.3) → Linear(64→1) → Sigmoid
        │
        ▼
  Output: tremor probability [0, 1]
```

### Training

- **Preprocessing**: Per-channel z-score normalization (scaler parameters embedded in the exported CoreML model metadata)
- **Split**: 70 / 15 / 15 stratified train / validation / test
- **Class balancing**: `WeightedRandomSampler` for minority class oversampling
- **Optimizer**: Adam (weight_decay=1e-4) with CosineAnnealingLR scheduler
- **Loss**: Binary cross-entropy
- **Early stopping**: Best validation loss checkpoint across 30 epochs
- **Export**: PyTorch → TorchScript trace → CoreML via `coremltools` (target: watchOS 7+)

### On-Device Inference

The app samples at 100 Hz with a 200-sample sliding window (50% overlap). For inference, each window is downsampled to 128 samples at 50 Hz, z-score normalized using scaler parameters from the model's metadata, then classified. Results feed into the adaptive haptic engine and the learning pipeline.

---

## Notable Algorithms

**Adaptive IIR Notch Filter** — A 2nd-order bandstop filter centered on the detected tremor frequency. Uses a jerk-based intentional-motion detector (threshold: 2.5 g/s) to distinguish voluntary movements from tremor. The blend factor ramps up slowly (0.4s) and releases quickly (0.1s) to preserve intentional motion.

**Exponential Moving Average Learning** — With alpha=0.1, the tremor profile adapts incrementally across sessions, persisting via UserDefaults every 10 observations. After calibration, the learned dominant frequency directly drives haptic timing.

**Live Efficacy Measurement** — Collects amplitude samples during a 10-second baseline window, then continuously compares against stimulation-period samples to compute real-time tremor reduction percentage.

---

## Requirements

- **iOS 17.0+** / **watchOS 10.0+**
- **Xcode 15+**
- Apple Watch with motion sensors (Series 4 or later recommended)
- HealthKit entitlement (optional, for workout logging)

### ML Model Training (optional)

- Python 3.9+
- PyTorch, coremltools, scikit-learn, NumPy

```bash
pip install torch coremltools scikit-learn numpy
python train_tremor_model.py
```

---

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/ank-krishna/tremormitigationapp.git
   ```

2. Open `TremorMitigationApp.xcodeproj` in Xcode.

3. Select your target device (iPhone or Apple Watch) and build.

4. On first launch, complete the onboarding flow and grant motion and HealthKit permissions when prompted.

---

## Project Structure

```
TremorMitigationApp/
├── TremorMitigation/                # Shared core logic + iOS views
│   ├── TremorDetector.swift         # Real-time FFT-based tremor detection
│   ├── TremorClassifier.swift       # CoreML / heuristic classification
│   ├── TremorFilter.swift           # Adaptive IIR notch filter
│   ├── TremorLearningEngine.swift   # EMA-based profile learning
│   ├── AdaptiveHapticEngine.swift   # CoreHaptics-based haptic output (iOS)
│   ├── StimulationService.swift     # Central session controller
│   ├── HealthKitManager.swift       # HealthKit integration
│   ├── SettingsManager.swift        # Persistence and session history
│   └── *View.swift                  # SwiftUI views (iOS)
├── TremorMitigation Watch App/      # watchOS-specific views and haptic engine
│   ├── WatchActiveSessionView.swift # Digital Crown control, confidence ring
│   ├── AdaptiveHapticEngine.swift   # WatchKit-based haptic output
│   └── Watch*View.swift             # SwiftUI views (watchOS)
├── TremorCoreMLClassifier.mlmodel   # Trained CoreML model
├── train_tremor_model.py            # PyTorch training + CoreML export script
└── Parkinson-s-Disease-Tremor-Dataset/  # Clinical tremor dataset
```

---

## Disclaimer

TremorCalm is a research and assistive tool. It is **not** a medical device and has not been evaluated or approved by the FDA or any regulatory body. It is not intended to diagnose, treat, cure, or prevent any disease. Always consult a qualified healthcare professional for medical advice regarding Parkinson's disease or any movement disorder.

---

## License

All rights reserved.
