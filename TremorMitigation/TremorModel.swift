//
//  TremorModel.swift
//  TremorMitigationApp
//
//  On-device tremor profile learned incrementally across sessions.
//

import Foundation

/// Persistent tremor profile built from observed tremor data.
/// Refined session-over-session using exponential moving averages.
struct TremorProfile: Codable {

    // MARK: - Learned Parameters

    /// EMA-smoothed dominant tremor frequency (Hz), valid range 3–12 Hz.
    var dominantFrequency: Double = 6.0

    /// EMA-smoothed mean acceleration magnitude during tremor (g).
    var meanAmplitude: Double = 0.05

    // MARK: - Calibration Counters

    /// Total tremor observations (individual FFT windows with tremor detected).
    var observationCount: Int = 0

    /// Number of completed sessions that contributed data.
    var sessionCount: Int = 0

    /// Minimum observations required before the profile is considered reliable.
    static let calibrationThreshold = 20

    /// Whether the profile has accumulated enough data to be reliable.
    var isCalibrated: Bool { observationCount >= TremorProfile.calibrationThreshold }

    // MARK: - Metadata

    var lastUpdated: Date = Date()

    // MARK: - Derived Haptic Parameters

    /// The haptic frequency to use. Falls back to 6 Hz before calibration.
    var recommendedHapticFrequency: Double {
        isCalibrated ? dominantFrequency : 6.0
    }

    /// Timer interval (seconds) between haptic pulses at the recommended frequency.
    var hapticInterval: TimeInterval {
        1.0 / max(3.0, min(recommendedHapticFrequency, 12.0))
    }
}
