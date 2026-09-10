import Foundation

// MARK: - Stimulation Types
enum StimulationType: String, CaseIterable {
    case vibration = "vibration"
    case electrical = "electrical"
    case combined = "combined"
    
    var displayName: String {
        switch self {
        case .vibration:
            return "Vibration"
        case .electrical:
            return "Electrical"
        case .combined:
            return "Combined"
        }
    }
    
    var iconName: String {
        switch self {
        case .vibration:
            return "waveform.path.ecg"
        case .electrical:
            return "bolt.fill"
        case .combined:
            return "waveform.path.ecg.rectangle"
        }
    }
}

// MARK: - Stimulation Intensity
enum StimulationIntensity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
    
    var vibrationLevel: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        }
    }
    
    var electricalLevel: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        }
    }
}

// MARK: - Session Duration
enum SessionDuration: String, CaseIterable {
    case fiveMinutes = "5min"
    case tenMinutes = "10min"
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case sixtyMinutes = "60min"
    
    var displayName: String {
        switch self {
        case .fiveMinutes:
            return "5 min"
        case .tenMinutes:
            return "10 min"
        case .fifteenMinutes:
            return "15 min"
        case .thirtyMinutes:
            return "30 min"
        case .sixtyMinutes:
            return "60 min"
        }
    }
    
    var durationInSeconds: TimeInterval {
        switch self {
        case .fiveMinutes:
            return 5 * 60
        case .tenMinutes:
            return 10 * 60
        case .fifteenMinutes:
            return 15 * 60
        case .thirtyMinutes:
            return 30 * 60
        case .sixtyMinutes:
            return 60 * 60
        }
    }
}

// MARK: - Stimulation Settings
struct StimulationSettings {
    let stimulationType: StimulationType
    let intensity: StimulationIntensity
    let sessionDuration: SessionDuration
    let lastSessionDate: Date?
    
    var isValid: Bool {
        // Check if enough time has passed since last session
        if let lastSession = lastSessionDate {
            let timeSinceLastSession = Date().timeIntervalSince(lastSession)
            let minRestPeriod: TimeInterval = 5 * 60 // 5 minutes
            return timeSinceLastSession >= minRestPeriod
        }
        return true
    }
}

// MARK: - Stimulation Session
struct StimulationSession {
    let startTime: Date
    let endTime: Date?
    let settings: StimulationSettings
    let wasCompleted: Bool
    let userStopped: Bool
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    var isActive: Bool {
        return endTime == nil
    }
} 