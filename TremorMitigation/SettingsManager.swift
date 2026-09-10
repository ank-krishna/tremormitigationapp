import Foundation
import SwiftUI

// MARK: - Session Record (persisted history)

struct SessionRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var stimulationType: String
    var intensity: String
    var durationSeconds: TimeInterval
    var wasCompleted: Bool
    var userStopped: Bool
    /// Tremor amplitude reduction during stimulation (0–1), nil if efficacy tracking was off.
    var efficacy: Double?

    var formattedDuration: String {
        let m = Int(durationSeconds) / 60
        let s = Int(durationSeconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    var formattedEfficacy: String? {
        guard let e = efficacy else { return nil }
        if e > 0 {
            return String(format: "↓%.0f%%", e * 100)
        } else if e < 0 {
            return String(format: "↑%.0f%%", abs(e) * 100)
        } else {
            return "—"
        }
    }
}

// MARK: - Settings Manager

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var dailySessionLimit: Int       = 8
    @Published var lastSessionDate: Date?
    @Published var enableHapticFeedback: Bool   = true
    @Published var enableSoundAlerts: Bool      = false
    @Published var autoPauseOnInactivity: Bool  = true
    @Published var emergencyStopEnabled: Bool   = true
    @Published var enableEfficacyTracking: Bool = false

    @Published private(set) var sessionHistory: [SessionRecord] = []

    private let defaults = UserDefaults.standard

    private enum Key {
        static let dailyLimit       = "dailySessionLimit"
        static let lastSessionDate  = "lastSessionDate"
        static let hapticFeedback   = "enableHapticFeedback"
        static let soundAlerts      = "enableSoundAlerts"
        static let autoPause        = "autoPauseOnInactivity"
        static let emergencyStop    = "emergencyStopEnabled"
        static let efficacyTracking = "enableEfficacyTracking"
        static let sessionHistory   = "com.tremorapp.sessionHistory.v1"
    }

    private init() { load() }

    // MARK: - Persistence

    private func load() {
        dailySessionLimit      = defaults.integer(forKey: Key.dailyLimit).nonZero ?? 8
        lastSessionDate        = defaults.object(forKey: Key.lastSessionDate) as? Date
        // Bool keys default false unless explicitly saved true
        enableHapticFeedback   = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? true
        enableSoundAlerts      = defaults.object(forKey: Key.soundAlerts)    as? Bool ?? false
        autoPauseOnInactivity  = defaults.object(forKey: Key.autoPause)      as? Bool ?? true
        emergencyStopEnabled   = defaults.object(forKey: Key.emergencyStop)  as? Bool ?? true
        enableEfficacyTracking = defaults.object(forKey: Key.efficacyTracking) as? Bool ?? false

        if let data = defaults.data(forKey: Key.sessionHistory),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessionHistory = decoded
        }
    }

    private func save() {
        defaults.set(dailySessionLimit,     forKey: Key.dailyLimit)
        defaults.set(lastSessionDate,       forKey: Key.lastSessionDate)
        defaults.set(enableHapticFeedback,  forKey: Key.hapticFeedback)
        defaults.set(enableSoundAlerts,     forKey: Key.soundAlerts)
        defaults.set(autoPauseOnInactivity, forKey: Key.autoPause)
        defaults.set(emergencyStopEnabled,  forKey: Key.emergencyStop)
        defaults.set(enableEfficacyTracking, forKey: Key.efficacyTracking)

        if let data = try? JSONEncoder().encode(sessionHistory) {
            defaults.set(data, forKey: Key.sessionHistory)
        }
    }

    // MARK: - Session history

    func recordSession(_ record: SessionRecord) {
        sessionHistory.insert(record, at: 0)   // newest first
        // Keep last 200 sessions
        if sessionHistory.count > 200 { sessionHistory = Array(sessionHistory.prefix(200)) }
        lastSessionDate = record.startTime
        save()
    }

    func getTodaySessionCount() -> Int {
        let calendar = Calendar.current
        return sessionHistory.filter { calendar.isDateInToday($0.startTime) }.count
    }

    func canStartNewSession() -> Bool {
        getTodaySessionCount() < dailySessionLimit
    }

    func clearSessionHistory() {
        sessionHistory.removeAll()
        save()
    }

    func resetToDefaults() {
        dailySessionLimit     = 8
        lastSessionDate       = nil
        enableHapticFeedback  = true
        enableSoundAlerts     = false
        autoPauseOnInactivity = true
        emergencyStopEnabled  = true
        enableEfficacyTracking = false
        save()
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
