//
//  TremorDetector.swift
//  TremorMitigationApp
//
//  Real-time tremor detection pipeline using CoreMotion + FFT + adaptive filtering.
//
//  Data acquisition
//  ────────────────
//  • Samples both accelerometer and gyroscope at 100 Hz via CMDeviceMotion.
//  • Maintains a sliding window (2 s = 200 samples) with 50 % overlap so a new
//    analysis runs every second.
//
//  Detection
//  ─────────
//  • FFT over the magnitude window finds the dominant frequency and tremor-band
//    power ratio (3–12 Hz, covering both essential and Parkinson's tremor).
//  • TremorClassifier combines the FFT score with gyro variance and frequency
//    plausibility to emit a continuous confidence value (0–1).
//  • isTremorDetected = (confidence ≥ 0.5).
//
//  Mitigation
//  ──────────
//  • TremorFilter applies a per-sample adaptive IIR notch filter centred on the
//    detected frequency. It blends between filtered and raw based on jerk magnitude
//    so voluntary fast movements are passed through unmodified.
//  • filteredAcceleration is updated on every sample and can drive downstream
//    motion-compensation logic.
//

import Foundation
import CoreMotion
import Accelerate

@MainActor
final class TremorDetector: ObservableObject {

    // MARK: - Published outputs

    /// True when classifier confidence ≥ 0.5.
    @Published private(set) var isTremorDetected: Bool = false
    /// Dominant frequency within the tremor band from FFT (Hz).
    @Published private(set) var dominantHz: Double = 0
    /// Classifier confidence score (0–1).  0 = no tremor, 1 = certain tremor.
    @Published private(set) var tremorScore: Double = 0
    /// RMS acceleration magnitude of the last analysis window (g).
    @Published private(set) var amplitude: Double = 0
    /// Gravity-free user acceleration after adaptive tremor suppression (g).
    @Published private(set) var filteredAcceleration: SIMD3<Double> = .zero

    // MARK: - Sub-components

    private let motionManager = CMMotionManager()
    private let classifier    = TremorClassifier()
    private let filter        = TremorFilter()

    // MARK: - Configuration

    private let sampleRateHz: Double
    private let windowSeconds: Double
    private let tremorBandHz:  ClosedRange<Double>
    private let confidenceThreshold: Double

    private var dt: Double   { 1.0 / sampleRateHz }
    private var windowSize: Int { Int(sampleRateHz * windowSeconds) }

    // MARK: - Sliding-window buffers

    /// Magnitude buffer for FFT analysis.
    private var magBuffer: [Double] = []
    /// Per-axis user-acceleration buffer for the classifier and filter.
    private var accelBuffer: [SIMD3<Double>] = []
    /// Per-axis rotation-rate buffer for the classifier.
    private var gyroBuffer: [SIMD3<Double>] = []

    // MARK: - Init

    init(
        sampleRateHz: Double           = 100,
        windowSeconds: Double          = 2.0,
        tremorBandHz: ClosedRange<Double> = 3.0...12.0,
        confidenceThreshold: Double    = 0.50
    ) {
        self.sampleRateHz        = sampleRateHz
        self.windowSeconds       = windowSeconds
        self.tremorBandHz        = tremorBandHz
        self.confidenceThreshold = confidenceThreshold

        let cap = Int(sampleRateHz * windowSeconds) + 16
        magBuffer.reserveCapacity(cap)
        accelBuffer.reserveCapacity(cap)
        gyroBuffer.reserveCapacity(cap)
    }

    // MARK: - Start / Stop

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            resetOutputs()
            return
        }
        motionManager.deviceMotionUpdateInterval = dt
        // .main queue keeps @Published mutations on the main actor
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, error == nil, let motion else { return }

            let ua = motion.userAcceleration
            let rr = motion.rotationRate

            let accel = SIMD3<Double>(ua.x, ua.y, ua.z)  // gravity removed
            let gyro  = SIMD3<Double>(rr.x, rr.y, rr.z)  // rad/s
            self.pushSample(accel: accel, gyro: gyro)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        magBuffer.removeAll(keepingCapacity: true)
        accelBuffer.removeAll(keepingCapacity: true)
        gyroBuffer.removeAll(keepingCapacity: true)
        filter.reset()
        resetOutputs()
    }

    // MARK: - Per-sample ingestion

    private func pushSample(accel: SIMD3<Double>, gyro: SIMD3<Double>) {
        // 1. Real-time filter — runs on every sample for low latency
        filteredAcceleration = filter.process(
            accel,
            sampleRate: sampleRateHz,
            tremorConfidence: tremorScore   // uses the last window's confidence
        )

        // 2. Buffer for windowed FFT analysis
        let magnitudeG = sqrt(accel.x*accel.x + accel.y*accel.y + accel.z*accel.z)
        magBuffer.append(magnitudeG)
        accelBuffer.append(accel)
        gyroBuffer.append(gyro)

        // 3. Run analysis when we have a full window; slide by half
        if magBuffer.count >= windowSize {
            let magW   = Array(magBuffer.suffix(windowSize))
            let accelW = Array(accelBuffer.suffix(windowSize))
            let gyroW  = Array(gyroBuffer.suffix(windowSize))
            analyze(magWindow: magW, accelWindow: accelW, gyroWindow: gyroW)

            let keep = windowSize / 2
            magBuffer   = Array(magBuffer.suffix(keep))
            accelBuffer = Array(accelBuffer.suffix(keep))
            gyroBuffer  = Array(gyroBuffer.suffix(keep))
        }
    }

    // MARK: - Windowed analysis

    private func analyze(
        magWindow: [Double],
        accelWindow: [SIMD3<Double>],
        gyroWindow: [SIMD3<Double>]
    ) {
        // RMS amplitude of the window
        var rms = 0.0
        vDSP_rmsqvD(magWindow, 1, &rms, vDSP_Length(magWindow.count))
        amplitude = rms

        // FFT → dominant frequency + band power ratio
        guard let (domHz, fftRatio) = spectralAnalysis(magWindow) else { return }

        // Multi-signal confidence from classifier
        let confidence = classifier.classify(
            accelWindow: accelWindow,
            gyroWindow: gyroWindow,
            fftScore: fftRatio,
            dominantHz: domHz
        )

        dominantHz    = domHz
        tremorScore   = confidence
        isTremorDetected = confidence >= confidenceThreshold

        // Notify filter of updated tremor frequency for notch tuning
        if isTremorDetected {
            filter.setTremorFrequency(domHz, sampleRate: sampleRateHz)
        }
    }

    // MARK: - Spectral analysis (FFT)

    /// Returns (dominantHz, bandPowerRatio) or nil if the window is too short.
    private func spectralAnalysis(_ samples: [Double]) -> (hz: Double, ratio: Double)? {
        var x = samples

        // Remove DC offset
        var mean = 0.0
        vDSP_meanvD(x, 1, &mean, vDSP_Length(x.count))
        var negMean = -mean
        vDSP_vsaddD(x, 1, &negMean, &x, 1, vDSP_Length(x.count))

        // Hann window to reduce spectral leakage
        var hann = [Double](repeating: 0, count: x.count)
        vDSP_hann_windowD(&hann, vDSP_Length(x.count), Int32(vDSP_HANN_NORM))
        vDSP_vmulD(x, 1, hann, 1, &x, 1, vDSP_Length(x.count))

        // Pad / truncate to nearest power of 2
        let log2n = vDSP_Length(floor(log2(Double(x.count))))
        let fftN  = 1 << log2n
        guard fftN >= 64 else { return nil }
        if x.count != fftN { x = Array(x.prefix(fftN)) }

        guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        var real  = x
        var imag  = [Double](repeating: 0, count: fftN)
        var power = [Double](repeating: 0, count: fftN / 2)

        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPDoubleSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )
                vDSP_fft_zipD(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                for k in 0..<power.count {
                    let re = split.realp[k], im = split.imagp[k]
                    power[k] = re*re + im*im
                }
            }
        }

        let binHz   = sampleRateHz / Double(fftN)
        let lowBin  = max(1, Int(floor(tremorBandHz.lowerBound / binHz)))
        let highBin = min(power.count - 1, Int(ceil(tremorBandHz.upperBound / binHz)))
        guard lowBin < highBin else { return nil }

        let total     = power.reduce(0, +)
        let bandPower = power[lowBin...highBin].reduce(0, +)
        let ratio     = total > 0 ? bandPower / total : 0

        var peakBin = lowBin, peakVal = -Double.infinity
        for (i, val) in power[lowBin...highBin].enumerated() {
            if val > peakVal { peakVal = val; peakBin = lowBin + i }
        }

        return (Double(peakBin) * binHz, ratio)
    }

    // MARK: - Helpers

    private func resetOutputs() {
        isTremorDetected    = false
        dominantHz          = 0
        tremorScore         = 0
        amplitude           = 0
        filteredAcceleration = .zero
    }
}
