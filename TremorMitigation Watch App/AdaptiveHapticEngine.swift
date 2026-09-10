//
//  AdaptiveHapticEngine.swift
//  TremorMitigation Watch App
//
//  WatchKit-based adaptive haptic engine for watchOS.
//  Generates rhythmic WKHapticType pulses at the user's tremor frequency via Timer.
//

import Foundation
import WatchKit

@MainActor
final class AdaptiveHapticEngine {

    private(set) var isRunning = false

    private var hapticTimer: Timer?
    private var currentInterval: TimeInterval = 1.0 / 6.0
    private var currentType: WKHapticType = .click

    // MARK: - Lifecycle

    func start(profile: TremorProfile,
               stimulationType: StimulationType,
               intensity: StimulationIntensity) {
        isRunning = true
        currentInterval = profile.hapticInterval
        currentType = hapticType(for: intensity)
        scheduleTimer()
    }

    func update(tremorDetected: Bool, frequency: Double, score: Double) {
        guard isRunning else { return }
        guard tremorDetected, frequency >= 3.0, frequency <= 12.0 else { return }

        let newInterval = 1.0 / frequency
        if abs(newInterval - currentInterval) > 0.02 {
            currentInterval = newInterval
            scheduleTimer()
        }
    }

    func stop() {
        isRunning = false
        hapticTimer?.invalidate()
        hapticTimer = nil
    }

    // MARK: - Private

    private func scheduleTimer() {
        hapticTimer?.invalidate()
        hapticTimer = Timer.scheduledTimer(withTimeInterval: currentInterval,
                                           repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                WKInterfaceDevice.current().play(self.currentType)
            }
        }
    }

    private func hapticType(for intensity: StimulationIntensity) -> WKHapticType {
        switch intensity {
        case .low:    return .directionDown
        case .medium: return .click
        case .high:   return .notification
        }
    }
}
