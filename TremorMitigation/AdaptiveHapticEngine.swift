//
//  AdaptiveHapticEngine.swift
//  TremorMitigationApp
//
//  CoreHaptics-based adaptive haptic engine for iOS/macOS.
//  Generates rhythmic pulses tuned to the user's detected tremor frequency.
//

import Foundation
import CoreHaptics

@MainActor
final class AdaptiveHapticEngine {

    private(set) var isRunning = false

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    private var currentFrequency: Double = 6.0
    private var currentIntensity: Float = 0.5

    private let frequencyChangeTolerance: Double = 0.5
    private let patternDuration: Double = 30.0

    // MARK: - Lifecycle

    func start(profile: TremorProfile,
               stimulationType: StimulationType,
               intensity: StimulationIntensity) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let eng = try CHHapticEngine()
            eng.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.isRunning = false }
            }
            eng.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    try? self.engine?.start()
                    if self.isRunning {
                        try? self.playPattern(frequency: self.currentFrequency,
                                              intensity: self.currentIntensity)
                    }
                }
            }
            try eng.start()
            engine = eng
            isRunning = true

            currentFrequency = profile.recommendedHapticFrequency
            currentIntensity = baseIntensity(for: intensity)
            try playPattern(frequency: currentFrequency, intensity: currentIntensity)
        } catch {
            isRunning = false
        }
    }

    func update(tremorDetected: Bool, frequency: Double, score: Double) {
        guard isRunning else { return }

        let clampedFreq = max(4.0, min(frequency, 8.0))
        let targetFreq = tremorDetected ? clampedFreq : currentFrequency
        let targetIntensity: Float = tremorDetected
            ? Float(min(0.3 + score * 0.7, 1.0))
            : max(currentIntensity * 0.5, 0.2)

        let freqShifted = tremorDetected
            && abs(clampedFreq - currentFrequency) > frequencyChangeTolerance
        let intensityShifted = abs(targetIntensity - currentIntensity) > 0.15

        if freqShifted {
            currentFrequency = targetFreq
            currentIntensity = targetIntensity
            try? playPattern(frequency: currentFrequency, intensity: currentIntensity)
        } else if intensityShifted {
            currentIntensity = targetIntensity
            try? player?.sendParameters(
                [CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                          value: targetIntensity,
                                          relativeTime: CHHapticTimeImmediate)],
                atTime: CHHapticTimeImmediate
            )
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
        engine = nil
        isRunning = false
    }

    // MARK: - Private

    private func playPattern(frequency: Double, intensity: Float) throws {
        guard let engine else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)

        let pattern = try makeRhythmicPattern(frequency: frequency, intensity: intensity)
        let newPlayer = try engine.makeAdvancedPlayer(with: pattern)

        newPlayer.completionHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                try? self.playPattern(frequency: self.currentFrequency,
                                      intensity: self.currentIntensity)
            }
        }

        try newPlayer.start(atTime: CHHapticTimeImmediate)
        player = newPlayer
    }

    private func makeRhythmicPattern(frequency: Double, intensity: Float) throws -> CHHapticPattern {
        let interval = 1.0 / max(4.0, min(frequency, 8.0))
        var events: [CHHapticEvent] = []
        var t = 0.0
        while t < patternDuration {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: t
            ))
            t += interval
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private func baseIntensity(for level: StimulationIntensity) -> Float {
        switch level {
        case .low:    return 0.3
        case .medium: return 0.6
        case .high:   return 0.9
        }
    }
}
