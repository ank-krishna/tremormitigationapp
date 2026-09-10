//
//  TremorLearningEngine.swift
//  TremorMitigationApp
//
//  Incrementally learns each user's tremor pattern across sessions.
//  Uses exponential moving averages (EMA) to refine the TremorProfile and
//  persists it to UserDefaults so learning survives app restarts.
//

import Foundation
import Combine

@MainActor
final class TremorLearningEngine: ObservableObject {

    @Published private(set) var profile: TremorProfile

    // EMA smoothing factor. α=0.1 → slow, stable adaptation across many sessions.
    private let alpha: Double = 0.1
    private let storageKey = "com.tremorapp.tremorProfile.v1"

    init() {
        self.profile = TremorLearningEngine.loadProfile() ?? TremorProfile()
    }

    // MARK: - Observation

    /// Record a single tremor window into the profile.
    /// - Parameters:
    ///   - frequency: Dominant frequency from FFT (Hz). Only 4–8 Hz range accepted.
    ///   - amplitude:  RMS acceleration magnitude of the window (g).
    ///   - score:      Tremor band power ratio from the detector (0–1).
    func observe(frequency: Double, amplitude: Double, score: Double) {
        guard (3.0...12.0).contains(frequency) else { return }

        profile.dominantFrequency = alpha * frequency + (1 - alpha) * profile.dominantFrequency
        profile.meanAmplitude     = alpha * amplitude + (1 - alpha) * max(profile.meanAmplitude, 1e-4)
        profile.observationCount += 1
        profile.lastUpdated = Date()

        // Persist every 10 observations to avoid excessive writes.
        if profile.observationCount % 10 == 0 {
            saveProfile()
        }
    }

    /// Call once at the end of each session (whether completed or user-stopped).
    func recordSessionEnd() {
        profile.sessionCount += 1
        saveProfile()
    }

    /// Erase all learned data and reset to defaults.
    func reset() {
        profile = TremorProfile()
        saveProfile()
    }

    // MARK: - Persistence

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadProfile() -> TremorProfile? {
        guard
            let data = UserDefaults.standard.data(forKey: "com.tremorapp.tremorProfile.v1"),
            let profile = try? JSONDecoder().decode(TremorProfile.self, from: data)
        else { return nil }
        return profile
    }
}
