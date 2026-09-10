//
//  StimulationService.swift
//  TremorMitigationApp (watchOS / iOS)
//
//  Central session controller: owns the session lifecycle, tremor detection,
//  haptic engine, and learning engine.
//

import Foundation
import HealthKit
import Combine

// MARK: - Protocol

protocol StimulationServiceProtocol {
    func startStimulation(with settings: StimulationSettings) async throws
    func stopStimulation() async
    func pauseStimulation() async
    func resumeStimulation() async
    var isActive: Bool { get }
    var currentSession: StimulationSession? { get }
}

// MARK: - StimulationService

final class StimulationService: NSObject, StimulationServiceProtocol, ObservableObject, @unchecked Sendable {

    static let shared = StimulationService()

    // MARK: - Published state

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentSession: StimulationSession?
    @Published private(set) var remainingTime: TimeInterval = 0

    @Published private(set) var tremorDetected: Bool = false
    @Published private(set) var tremorHz: Double = 0
    /// Classifier confidence (0–1). Primary signal for UI and learning.
    @Published private(set) var tremorScore: Double = 0
    /// Tremor-suppressed gravity-free acceleration (g), updated at 100 Hz.
    @Published private(set) var filteredAcceleration: SIMD3<Double> = .zero

    @Published private(set) var tremorProfile: TremorProfile = TremorProfile()

    /// Live efficacy: proportion of tremor amplitude reduced (0–1). Negative = tremor worsened.
    @Published private(set) var liveEfficacy: Double?

    // MARK: - Dependencies

    private let settingsManager  = SettingsManager.shared
    private let healthKitManager = HealthKitManager.shared

    @MainActor private lazy var tremorDetector = TremorDetector()
    @MainActor private lazy var learningEngine = TremorLearningEngine()
    @MainActor private lazy var hapticEngine   = AdaptiveHapticEngine()

    private var cancellables  = Set<AnyCancellable>()
    private var sessionTimer: Timer?

    // Auto-pause inactivity tracking
    private var inactivityTicks:       Int    = 0
    private let inactivityTimeout:     Int    = 60
    private let inactivityMinAmplitude: Double = 0.01

    // HealthKit snapshot collection (one every 30 seconds)
    private var sessionSnapshots: [TremorSnapshot] = []
    private var snapshotTick:     Int = 0
    private let snapshotInterval: Int = 30

    // Efficacy measurement
    // Baseline: amplitude samples during the first 10 seconds (before stimulation takes effect).
    // During:   amplitude samples after baseline window.
    // Efficacy = (baselineMean - duringMean) / baselineMean
    private var baselineAmplitudes: [Double] = []
    private var duringAmplitudes:   [Double] = []
    private let baselineWindowSec:  Int = 10
    private var sessionElapsedSec:  Int = 0

    // MARK: - Init

    override init() {
        super.init()
        Task { @MainActor in bindTremorDetector() }
    }

    // MARK: - Bindings

    @MainActor
    private func bindTremorDetector() {
        tremorDetector.$isTremorDetected
            .sink { [weak self] v in self?.tremorDetected = v }
            .store(in: &cancellables)

        tremorDetector.$dominantHz
            .sink { [weak self] v in self?.tremorHz = v }
            .store(in: &cancellables)

        tremorDetector.$tremorScore
            .sink { [weak self] score in
                guard let self else { return }
                self.tremorScore = score

                let hz       = self.tremorDetector.dominantHz
                let detected = self.tremorDetector.isTremorDetected
                let amp      = self.tremorDetector.amplitude

                if detected && hz > 0 {
                    self.learningEngine.observe(frequency: hz, amplitude: amp, score: score)
                    self.tremorProfile = self.learningEngine.profile
                }

                self.hapticEngine.update(tremorDetected: detected, frequency: hz, score: score)
            }
            .store(in: &cancellables)

        tremorDetector.$filteredAcceleration
            .sink { [weak self] v in self?.filteredAcceleration = v }
            .store(in: &cancellables)

        learningEngine.$profile
            .sink { [weak self] profile in self?.tremorProfile = profile }
            .store(in: &cancellables)
    }

    // MARK: - Public session API

    func startStimulation(with settings: StimulationSettings) async throws {
        guard !isActive else { throw StimulationError.sessionAlreadyActive }
        guard settings.isValid else { throw StimulationError.dailyLimitExceeded }

        // Enforce daily limit from persisted history
        guard settingsManager.canStartNewSession() else {
            throw StimulationError.dailyLimitExceeded
        }

        await MainActor.run {
            self.isActive       = true
            self.currentSession = StimulationSession(
                startTime: Date(), endTime: nil,
                settings: settings, wasCompleted: false, userStopped: false
            )
            self.remainingTime    = settings.sessionDuration.durationInSeconds
            self.inactivityTicks  = 0
            self.sessionSnapshots    = []
            self.snapshotTick       = 0
            self.baselineAmplitudes = []
            self.duringAmplitudes   = []
            self.sessionElapsedSec  = 0
            self.liveEfficacy       = nil
        }

        await MainActor.run { tremorDetector.start() }
        try await startStimulationType(settings.stimulationType, intensity: settings.intensity)
        await startSessionTimer(duration: settings.sessionDuration.durationInSeconds)
    }

    func stopStimulation() async {
        await stopAllStimulation()
        await MainActor.run {
            tremorDetector.stop()
            learningEngine.recordSessionEnd()
        }

        let snapshots = await MainActor.run { self.sessionSnapshots }
        await MainActor.run {
            if let session = currentSession {
                let end    = Date()
                let record = makeRecord(session: session, endTime: end,
                                        wasCompleted: false, userStopped: true)
                settingsManager.recordSession(record)

                let stimType = session.settings.stimulationType.rawValue
                let start    = session.startTime
                let eff      = self.settingsManager.enableEfficacyTracking ? self.computeEfficacy() : nil
                Task {
                    await self.healthKitManager.saveSession(
                        start: start, end: end,
                        stimulationType: stimType, snapshots: snapshots,
                        efficacy: eff
                    )
                }

                self.currentSession = StimulationSession(
                    startTime: session.startTime, endTime: end,
                    settings: session.settings, wasCompleted: false, userStopped: true
                )
            }
            self.isActive         = false
            self.remainingTime    = 0
            self.inactivityTicks  = 0
            self.sessionSnapshots = []
            self.snapshotTick     = 0
        }

        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    func pauseStimulation() async {
        await pauseAllStimulation()
        sessionTimer?.invalidate()
        await MainActor.run {
            tremorDetector.stop()
            inactivityTicks = 0
        }
    }

    func resumeStimulation() async {
        // Fix: guard against expired remaining time to prevent infinite open session
        guard let session = currentSession, remainingTime > 0 else {
            await completeSession()
            return
        }

        await MainActor.run { tremorDetector.start() }
        try? await startStimulationType(session.settings.stimulationType,
                                        intensity: session.settings.intensity)
        await startSessionTimer(duration: remainingTime)
    }

    /// Erases the learned tremor profile.
    @MainActor
    func resetTremorProfile() {
        learningEngine.reset()
        tremorProfile = learningEngine.profile
    }

    // MARK: - Private stimulation control

    private func startStimulationType(_ type: StimulationType,
                                      intensity: StimulationIntensity) async throws {
        // Respect the haptic feedback setting
        guard settingsManager.enableHapticFeedback else { return }

        await MainActor.run {
            hapticEngine.start(profile: learningEngine.profile,
                               stimulationType: type,
                               intensity: intensity)
        }
    }

    private func stopAllStimulation() async {
        await MainActor.run { hapticEngine.stop() }
    }

    private func pauseAllStimulation() async {
        await MainActor.run { hapticEngine.stop() }
    }

    // MARK: - Timer

    private func startSessionTimer(duration: TimeInterval) async {
        await MainActor.run {
            self.sessionTimer?.invalidate()
            self.sessionTimer = nil
            self.remainingTime = duration
        }

        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.remainingTime > 0 {
                    self.remainingTime -= 1
                    self.snapshotTick += 1
                    if self.snapshotTick >= self.snapshotInterval {
                        self.snapshotTick = 0
                        let snap = TremorSnapshot(
                            timestamp:  Date(),
                            confidence: self.tremorScore,
                            hz:         self.tremorHz
                        )
                        self.sessionSnapshots.append(snap)
                    }
                    self.collectEfficacySample()
                    self.checkInactivity()
                } else {
                    await self.completeSession()
                }
            }
        }
    }

    @MainActor
    private func checkInactivity() {
        guard settingsManager.autoPauseOnInactivity, isActive else {
            inactivityTicks = 0
            return
        }
        if tremorDetector.amplitude < inactivityMinAmplitude {
            inactivityTicks += 1
            if inactivityTicks >= inactivityTimeout {
                inactivityTicks = 0
                Task { await self.pauseStimulation() }
            }
        } else {
            inactivityTicks = 0
        }
    }

    private func completeSession() async {
        await stopAllStimulation()
        await MainActor.run {
            tremorDetector.stop()
            learningEngine.recordSessionEnd()
        }

        let snapshots = await MainActor.run { self.sessionSnapshots }
        await MainActor.run {
            if let session = currentSession {
                let end    = Date()
                let record = makeRecord(session: session, endTime: end,
                                        wasCompleted: true, userStopped: false)
                settingsManager.recordSession(record)

                let stimType = session.settings.stimulationType.rawValue
                let start    = session.startTime
                let eff      = self.settingsManager.enableEfficacyTracking ? self.computeEfficacy() : nil
                Task {
                    await self.healthKitManager.saveSession(
                        start: start, end: end,
                        stimulationType: stimType, snapshots: snapshots,
                        efficacy: eff
                    )
                }

                self.currentSession = StimulationSession(
                    startTime: session.startTime, endTime: end,
                    settings: session.settings, wasCompleted: true, userStopped: false
                )
            }
            self.isActive         = false
            self.remainingTime    = 0
            self.inactivityTicks  = 0
            self.sessionSnapshots = []
            self.snapshotTick     = 0
        }

        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Efficacy measurement

    @MainActor
    private func collectEfficacySample() {
        guard settingsManager.enableEfficacyTracking else { return }

        sessionElapsedSec += 1
        let amp = tremorDetector.amplitude

        // Only record when there's actual motion (ignore wrist-down periods)
        guard amp > inactivityMinAmplitude else { return }

        if sessionElapsedSec <= baselineWindowSec {
            baselineAmplitudes.append(amp)
        } else {
            duringAmplitudes.append(amp)
            // Update live efficacy every 5 seconds after baseline
            if duringAmplitudes.count.isMultiple(of: 5) {
                liveEfficacy = computeEfficacy()
            }
        }
    }

    /// Computes efficacy as fractional reduction: positive = tremor reduced, negative = worsened.
    private func computeEfficacy() -> Double? {
        guard baselineAmplitudes.count >= 3, duringAmplitudes.count >= 3 else { return nil }
        let baselineMean = baselineAmplitudes.reduce(0, +) / Double(baselineAmplitudes.count)
        let duringMean   = duringAmplitudes.reduce(0, +) / Double(duringAmplitudes.count)
        guard baselineMean > 0.001 else { return nil }  // not enough tremor to measure
        return (baselineMean - duringMean) / baselineMean
    }

    // MARK: - Session record helpers

    private func makeRecord(session: StimulationSession,
                            endTime: Date,
                            wasCompleted: Bool,
                            userStopped: Bool) -> SessionRecord {
        SessionRecord(
            startTime:       session.startTime,
            endTime:         endTime,
            stimulationType: session.settings.stimulationType.rawValue,
            intensity:       session.settings.intensity.rawValue,
            durationSeconds: endTime.timeIntervalSince(session.startTime),
            wasCompleted:    wasCompleted,
            userStopped:     userStopped,
            efficacy:        settingsManager.enableEfficacyTracking ? computeEfficacy() : nil
        )
    }
}

// MARK: - Errors

enum StimulationError: Error, LocalizedError {
    case sessionAlreadyActive, dailyLimitExceeded, hardwareNotAvailable,
         safetyCheckFailed, invalidSettings

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:  return "A stimulation session is already active"
        case .dailyLimitExceeded:    return "Daily session limit has been reached"
        case .hardwareNotAvailable:  return "Required hardware is not available"
        case .safetyCheckFailed:     return "Safety check failed — session cannot start"
        case .invalidSettings:       return "Invalid stimulation settings"
        }
    }
}

// MARK: - Safety Manager

final class SafetyManager {
    static let shared = SafetyManager()

    private let maxContinuousDuration: TimeInterval = 3600
    private let minRestPeriod: TimeInterval = 300

    func validateSession(_ settings: StimulationSettings) -> Bool {
        guard settings.sessionDuration.durationInSeconds <= maxContinuousDuration else { return false }
        if let last = settings.lastSessionDate {
            guard Date().timeIntervalSince(last) >= minRestPeriod else { return false }
        }
        return true
    }

    func emergencyStop() {
        guard SettingsManager.shared.emergencyStopEnabled else { return }
        Task { await StimulationService.shared.stopStimulation() }
    }
}
