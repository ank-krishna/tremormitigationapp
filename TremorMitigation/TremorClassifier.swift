//
//  TremorClassifier.swift
//  TremorMitigationApp
//
//  Classifies incoming IMU windows as tremor vs. intentional motion,
//  outputting a continuous confidence score in [0, 1].
//
//  Two modes (automatic fallback)
//  ────────────────────────────────────────────────────────────────────────────
//  1. CoreML mode  — uses TremorCoreMLClassifier.mlmodel trained on the
//                    Parkinson's Disease Tremor Dataset (299 subjects, ~25k windows).
//                    Active once the model file is added to the Xcode target.
//
//  2. Heuristic mode — FFT band power + gyro variance + frequency plausibility.
//                      Used automatically when the CoreML model is unavailable.
//
//  CoreML integration steps
//  ────────────────────────
//  1. Run train_tremor_model.py (see project root) to produce
//     TremorCoreMLClassifier.mlmodel.
//  2. Drag the .mlmodel into Xcode → add to the TremorMitigation target.
//  3. Xcode auto-generates a Swift class named TremorCoreMLClassifier.
//     The classifier below will pick it up automatically on the next build.
//
//  Input / output contract
//  ────────────────────────
//  Input  : imuWindow       float32  MLMultiArray  shape (1, 128, 3)
//           — 128 time steps at 50 Hz × 3 accel axes, z-score normalised
//  Output : tremorProbability  float32  scalar in [0, 1]
//
//  The app samples at 100 Hz (200-sample window).  prepareMLInput() downsamples
//  to 50 Hz / 128 samples by taking every other sample, then z-score normalises
//  using the scaler parameters embedded in the model's metadata.
//

import Foundation
import CoreML

// SIMD3 Euclidean length helper
private func mag(_ v: SIMD3<Double>) -> Double { sqrt(v.x*v.x + v.y*v.y + v.z*v.z) }

final class TremorClassifier {

    // MARK: - CoreML model (loaded once at init)

    /// Set to true once TremorCoreMLClassifier.mlmodel is in the app bundle.
    private var mlModel: MLModel?

    /// Normalisation parameters embedded in the model metadata by train_tremor_model.py.
    /// Shape: [3]  — one mean / scale per accelerometer axis.
    private var scalerMean:  [Double] = [0, 0, 0]
    private var scalerScale: [Double] = [1, 1, 1]

    // MARK: - Init

    init() {
        loadCoreMLModel()
    }

    private func loadCoreMLModel() {
        // Looks for TremorCoreMLClassifier.mlmodelc in the app bundle.
        // This file is produced by:
        //   1. Running train_tremor_model.py  →  TremorCoreMLClassifier.mlmodel
        //   2. Dragging the .mlmodel into Xcode (it auto-compiles to .mlmodelc)
        // Until the model file is present this initialiser exits silently and the
        // heuristic classifier is used instead.
        guard
            let modelURL = Bundle.main.url(
                forResource: "TremorCoreMLClassifier", withExtension: "mlmodelc"
            ),
            let model = try? MLModel(contentsOf: modelURL)
        else { return }

        mlModel = model

        // Recover per-axis scaler parameters embedded by train_tremor_model.py
        let meta = model.modelDescription.metadata
        if let meanStr  = meta[MLModelMetadataKey(rawValue: "scaler_mean")] as? String,
           let scaleStr = meta[MLModelMetadataKey(rawValue: "scaler_scale")] as? String {
            let parsedMean  = meanStr.split(separator: ",").compactMap { Double($0) }
            let parsedScale = scaleStr.split(separator: ",").compactMap { Double($0) }
            if parsedMean.count == 3  { scalerMean  = parsedMean  }
            if parsedScale.count == 3 { scalerScale = parsedScale }
        }
    }

    // MARK: - Public interface

    /// Returns a tremor confidence score in [0, 1].
    ///
    /// - Parameters:
    ///   - accelWindow: Gravity-free user-acceleration samples (g) — 200 samples at 100 Hz.
    ///   - gyroWindow:  Rotation-rate samples (rad/s) — same length.
    ///   - fftScore:    Tremor-band power ratio from FFT (0–1).
    ///   - dominantHz:  Dominant frequency within the tremor band.
    func classify(
        accelWindow: [SIMD3<Double>],
        gyroWindow:  [SIMD3<Double>],
        fftScore:    Double,
        dominantHz:  Double
    ) -> Double {
        // Try CoreML first
        if let confidence = coreMLConfidence(accelWindow: accelWindow) {
            return confidence
        }
        // Fall back to heuristic when model is not loaded
        return heuristicScore(
            accelWindow: accelWindow,
            gyroWindow:  gyroWindow,
            fftScore:    fftScore,
            dominantHz:  dominantHz
        )
    }

    // MARK: - CoreML inference

    /// Downsample 200 samples@100Hz → 128 samples@50Hz, normalise, run model.
    private func coreMLConfidence(accelWindow: [SIMD3<Double>]) -> Double? {
        guard let model = mlModel else { return nil }
        guard accelWindow.count >= 128 else { return nil }

        // 1. Downsample: take every other sample to go from 200@100Hz to 100@50Hz,
        //    then pick the last 128 samples (or stride to exactly 128 from 200).
        //    Simple approach: stride by (count / 128) to spread evenly across the window.
        let stride = max(1, accelWindow.count / 128)
        var downsampled: [SIMD3<Double>] = []
        downsampled.reserveCapacity(128)
        var i = 0
        while downsampled.count < 128 && i < accelWindow.count {
            downsampled.append(accelWindow[i])
            i += stride
        }
        // Pad with zeros if we ended up short (shouldn't happen in practice)
        while downsampled.count < 128 {
            downsampled.append(.zero)
        }

        // 2. Build MLMultiArray  shape (1, 128, 3)
        guard let input = try? MLMultiArray(shape: [1, 128, 3], dataType: .float32)
        else { return nil }

        for t in 0..<128 {
            let axes: [Double] = [downsampled[t].x, downsampled[t].y, downsampled[t].z]
            for c in 0..<3 {
                // z-score normalise using scaler params from training
                let normalised = (axes[c] - scalerMean[c]) / max(scalerScale[c], 1e-8)
                input[[0, t, c] as [NSNumber]] = NSNumber(value: Float(normalised))
            }
        }

        // 3. Run inference
        let featureProvider = try? MLDictionaryFeatureProvider(
            dictionary: ["imuWindow": MLFeatureValue(multiArray: input)]
        )
        guard
            let provider = featureProvider,
            let output   = try? model.prediction(from: provider),
            let probArray = output.featureValue(for: "tremorProbability")?.multiArrayValue
        else { return nil }

        return Double(truncating: probArray[0])
    }

    // MARK: - Heuristic fallback

    private func heuristicScore(
        accelWindow: [SIMD3<Double>],
        gyroWindow:  [SIMD3<Double>],
        fftScore:    Double,
        dominantHz:  Double
    ) -> Double {
        guard !accelWindow.isEmpty else { return 0 }

        // Component 1 – FFT band power ratio (primary tremor signal)
        let fftContribution = 0.60 * fftScore

        // Component 2 – Gyro variance:
        //   Tremor produces consistent low-amplitude oscillation; high gyro variance
        //   suggests deliberate wrist rotation (intentional motion).
        let gyroVar = variance(gyroWindow.map { mag($0) })
        let gyroConfidence = 1.0 - min(gyroVar / 0.5, 1.0)
        let gyroContribution = 0.25 * gyroConfidence

        // Component 3 – Frequency plausibility:
        //   Core Parkinson's band (4–8 Hz) scores highest; 3–12 Hz edges score lower.
        let freqScore: Double
        if (4.0...8.0).contains(dominantHz) {
            freqScore = 1.0
        } else if (3.0...12.0).contains(dominantHz) {
            freqScore = 0.6
        } else {
            freqScore = 0.0
        }
        let freqContribution = 0.15 * freqScore

        return max(0.0, min(fftContribution + gyroContribution + freqContribution, 1.0))
    }

    // MARK: - Feature extraction (for CoreML input reference)

    /// Statistical feature vector extracted from a window.
    /// Matches what train_tremor_model.py's extractMLFeatures() produces —
    /// useful if you switch to a feature-vector model instead of a raw-signal CNN.
    func extractMLFeatures(
        accelWindow: [SIMD3<Double>],
        gyroWindow:  [SIMD3<Double>]
    ) -> [Double] {
        let accelMags = accelWindow.map { mag($0) }
        let gyroMags  = gyroWindow.map  { mag($0) }
        return [
            mean(accelMags),    stdDev(accelMags),
            mean(gyroMags),     stdDev(gyroMags),
            zeroCrossingRate(accelMags),
            zeroCrossingRate(gyroMags),
        ]
    }

    // MARK: - Statistics helpers

    private func mean(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        return v.reduce(0, +) / Double(v.count)
    }

    private func variance(_ v: [Double]) -> Double {
        guard v.count > 1 else { return 0 }
        let m = mean(v)
        return v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)
    }

    private func stdDev(_ v: [Double]) -> Double { sqrt(variance(v)) }

    private func zeroCrossingRate(_ v: [Double]) -> Double {
        guard v.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<v.count where (v[i] >= 0) != (v[i-1] >= 0) { crossings += 1 }
        return Double(crossings) / Double(v.count - 1)
    }
}
