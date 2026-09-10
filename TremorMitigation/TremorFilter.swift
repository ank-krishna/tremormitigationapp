//
//  TremorFilter.swift
//  TremorMitigationApp
//
//  Adaptive per-sample notch filter that suppresses detected tremor frequencies
//  while preserving intentional voluntary motion.
//
//  How it works
//  ────────────
//  1. Notch filter: a 2nd-order IIR bandstop filter is centered at the detected
//     tremor frequency. It attenuates a narrow band (±~1 Hz) around that frequency
//     while passing everything else essentially unchanged.
//
//  2. Intentional-motion detection (the hard part):
//     Tremors are involuntary, rhythmic oscillations — they build up gradually and
//     are relatively constant in frequency. Voluntary movements produce a sharp spike
//     in acceleration (high "jerk" = da/dt). By monitoring jerk magnitude per sample,
//     we can detect fast volitional gestures and temporarily blend the filter output
//     back toward the raw signal so the intended motion is not suppressed.
//
//     blendAlpha = 1.0  → output is fully filtered  (suppress tremor)
//     blendAlpha = 0.0  → output is fully raw        (preserve intentional motion)
//
//  3. The notch only engages when tremor confidence ≥ 0.5 (passed in from
//     TremorDetector so the filter is inactive during non-tremor periods).
//
//  Filter coefficients (2nd-order IIR notch)
//  ──────────────────────────────────────────
//  H(z) = (1 - 2cos(ω₀)z⁻¹ + z⁻²) / (1 - 2r·cos(ω₀)z⁻¹ + r²·z⁻²)
//
//  where  ω₀ = 2π·f₀/fₛ     (notch frequency in radians)
//         r  = 1 - π·BW/fₛ  (pole radius; r → 1 makes the notch narrower)
//
//  Difference equation (Direct Form II Transposed):
//  y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] − a1·y[n-1] − a2·y[n-2]
//

import Foundation

// SIMD3 Euclidean length helper (avoids module-scope ambiguity with simd_length)
private func mag(_ v: SIMD3<Double>) -> Double { sqrt(v.x*v.x + v.y*v.y + v.z*v.z) }

final class TremorFilter {

    // MARK: - Types

    private struct BiquadState {
        var x1: Double = 0, x2: Double = 0   // input delay line
        var y1: Double = 0, y2: Double = 0   // output delay line
    }

    private struct BiquadCoeffs {
        var b0: Double = 1, b1: Double = 0, b2: Double = 0
        var a1: Double = 0, a2: Double = 0
    }

    // MARK: - State

    // One biquad state per axis (x=0, y=1, z=2)
    private var states = [BiquadState(), BiquadState(), BiquadState()]
    private var coeffs = BiquadCoeffs()

    // Current notch parameters
    private var notchHz: Double   = 6.0
    private var bandwidthHz: Double = 2.0     // ±~1 Hz notch width
    private var sampleRate: Double  = 100.0

    // Blend factor — tracks how much filtering to apply this sample
    private var blendAlpha: Double = 0.0   // starts at 0 (passthrough) until tremor is confirmed

    // Jerk-based intentional-motion detection
    private var prevAccel: SIMD3<Double> = .zero
    /// Jerk threshold in g/s. Below this → rhythmic tremor oscillation.
    /// Above this → fast voluntary movement (e.g. reaching, gesturing).
    /// Tune based on user testing; 2–4 g/s covers most deliberate gestures.
    private let jerkThreshold: Double = 2.5

    // Blend dynamics
    /// How quickly blendAlpha rises toward 1.0 when tremor is active and no jerk.
    private let filterEngageRate: Double  = 0.04   // per sample at 100 Hz ≈ 0.4 s ramp-up
    /// How quickly blendAlpha falls toward 0.0 when intentional motion is detected.
    private let filterReleaseRate: Double = 0.20   // per sample at 100 Hz ≈ 0.1 s release

    // MARK: - Public interface

    /// Update the notch center frequency. Call whenever TremorDetector reports a new dominant Hz.
    /// - Parameters:
    ///   - hz: New tremor frequency in Hz (will be clamped to 3–12 Hz).
    ///   - sampleRate: Current sample rate in Hz.
    func setTremorFrequency(_ hz: Double, sampleRate fs: Double) {
        let clamped = max(3.0, min(hz, 12.0))
        // Only recompute coefficients when the frequency shifts meaningfully
        guard abs(clamped - notchHz) > 0.25 || abs(fs - sampleRate) > 0.5 else { return }
        notchHz    = clamped
        sampleRate = fs
        coeffs     = makeNotchCoeffs(f0: notchHz, fs: sampleRate, bw: bandwidthHz)
    }

    /// Process a single gravity-free user-acceleration sample in real time.
    ///
    /// - Parameters:
    ///   - accel: Raw user-acceleration vector (g), gravity removed by CoreMotion.
    ///   - sampleRate: Current sample rate in Hz.
    ///   - tremorConfidence: Classifier confidence (0–1). Filter is inactive below 0.5.
    /// - Returns: Tremor-suppressed acceleration vector.
    func process(
        _ accel: SIMD3<Double>,
        sampleRate: Double,
        tremorConfidence: Double
    ) -> SIMD3<Double> {
        // Compute jerk (rate-of-change of acceleration) for this sample
        let jerkMag = mag(accel - prevAccel) * sampleRate
        prevAccel = accel

        if tremorConfidence < 0.5 {
            // No tremor — gradually release the filter and pass through
            blendAlpha = max(0.0, blendAlpha - filterReleaseRate)
        } else if jerkMag > jerkThreshold {
            // Intentional fast movement — release filter quickly
            blendAlpha = max(0.0, blendAlpha - filterReleaseRate * 3.0)
        } else {
            // Tremor present, no intentional motion — ramp filter up
            blendAlpha = min(1.0, blendAlpha + filterEngageRate)
        }

        // If blend is negligible, skip filtering entirely (passthrough)
        guard blendAlpha > 0.01 else { return accel }

        // Apply notch filter independently on each axis
        let filtered = SIMD3<Double>(
            applyBiquad(accel.x, axis: 0),
            applyBiquad(accel.y, axis: 1),
            applyBiquad(accel.z, axis: 2)
        )

        // Weighted blend: preserve intentional motion component
        return blendAlpha * filtered + (1.0 - blendAlpha) * accel
    }

    /// Reset all filter state (call on session stop/pause).
    func reset() {
        states     = [BiquadState(), BiquadState(), BiquadState()]
        prevAccel  = .zero
        blendAlpha = 0.0
    }

    // MARK: - Private

    private func applyBiquad(_ x: Double, axis: Int) -> Double {
        let s  = states[axis]
        let y  = coeffs.b0 * x
                + coeffs.b1 * s.x1
                + coeffs.b2 * s.x2
                - coeffs.a1 * s.y1
                - coeffs.a2 * s.y2
        states[axis] = BiquadState(x1: x, x2: s.x1, y1: y, y2: s.y1)
        return y
    }

    /// Build 2nd-order IIR notch-filter coefficients.
    ///
    ///   H(z) = (1 - 2cos(ω₀)z⁻¹ + z⁻²) / (1 - 2r·cos(ω₀)z⁻¹ + r²·z⁻²)
    ///
    /// The zeros sit exactly on the unit circle at ±ω₀ (infinite attenuation at f₀).
    /// The poles are pulled inside the unit circle by factor r, controlling notch width.
    private func makeNotchCoeffs(f0: Double, fs: Double, bw: Double) -> BiquadCoeffs {
        let w0 = 2.0 * .pi * f0 / fs
        // r = 1 - π·BW/fs keeps the filter stable (|r| < 1 always for bw > 0)
        let r  = 1.0 - .pi * bw / fs
        return BiquadCoeffs(
            b0:  1.0,
            b1: -2.0 * cos(w0),
            b2:  1.0,
            a1: -2.0 * r * cos(w0),
            a2:  r * r
        )
    }
}
