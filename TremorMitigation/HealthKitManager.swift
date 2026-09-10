//
//  HealthKitManager.swift
//  TremorMitigationApp
//
//  Logs each session and its tremor episodes to HealthKit so the user can
//  track tremor timing, severity, frequency, and time-of-day patterns in the
//  Health app alongside their other health data.
//
//  What gets written
//  ─────────────────
//  • HKWorkout (.other)           — one per session, with metadata:
//      TremorCalm_StimulationType   "vibration" | "electrical" | "combined"
//      TremorCalm_AvgConfidence     classifier score averaged over session
//      TremorCalm_PeakConfidence    highest single-window score
//      TremorCalm_AvgTremorHz       mean dominant frequency during tremor episodes
//      TremorCalm_TremorPercent     % of session where tremor was detected
//
//  • HKCategorySample (.tremors)  — one per continuous tremor episode:
//      severity notPresent | mild | moderate | strong  (from confidence score)
//      metadata: TremorCalm_AvgHz — average Hz for that episode
//
//  Required Xcode project setup (cannot be done from code)
//  ────────────────────────────────────────────────────────
//  1. Add HealthKit capability to both targets
//     (Signing & Capabilities → + → HealthKit)
//  2. Add to both Info.plist files:
//     NSHealthUpdateUsageDescription
//       "TremorCalm records your tremor sessions to track patterns over time."
//

import Foundation
import HealthKit

// MARK: - Tremor snapshot (collected every 30 s during a session)

struct TremorSnapshot {
    let timestamp:  Date
    let confidence: Double   // classifier score 0–1
    let hz:         Double   // dominant tremor frequency (0 if not detected)
}

// MARK: - HealthKit Manager

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    // MARK: - Auth status

    enum AuthStatus { case notDetermined, authorized, denied, unavailable }
    @Published private(set) var authStatus: AuthStatus = .notDetermined

    // MARK: - Private

    private let store = HKHealthStore()

    // Tremors category type identifier — available iOS 13.6 / watchOS 7.0
    private let tremorIdentifier = HKCategoryTypeIdentifier(
        rawValue: "HKCategoryTypeIdentifierTremors"
    )

    // HKCategoryValueSeverity raw values (iOS 13.6+):
    //   notPresent = 1, mild = 2, moderate = 3, strong = 4
    private func severityValue(for confidence: Double) -> Int {
        switch confidence {
        case ..<0.30:          return 1  // notPresent
        case 0.30 ..< 0.50:   return 2  // mild
        case 0.50 ..< 0.75:   return 3  // moderate
        default:               return 4  // strong
        }
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let t = HKObjectType.categoryType(forIdentifier: tremorIdentifier) {
            types.insert(t)
        }
        return types
    }

    private init() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authStatus = .unavailable
            return
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authStatus = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: [])
            authStatus = .authorized
        } catch {
            authStatus = .denied
        }
    }

    // MARK: - Save session

    func saveSession(
        start:           Date,
        end:             Date,
        stimulationType: String,
        snapshots:       [TremorSnapshot],
        efficacy:        Double? = nil
    ) async {
        guard authStatus == .authorized,
              HKHealthStore.isHealthDataAvailable() else { return }

        // Build and save HKWorkout
        let workout = HKWorkout(
            activityType:      .other,
            start:             start,
            end:               end,
            workoutEvents:     nil,
            totalEnergyBurned: nil,
            totalDistance:     nil,
            metadata:          workoutMetadata(snapshots: snapshots, type: stimulationType, efficacy: efficacy)
        )
        do { try await store.save(workout) } catch { }

        // Build and save tremor episode samples
        let tremorSamples = tremorCategorySamples(snapshots: snapshots)
        if !tremorSamples.isEmpty {
            do { try await store.save(tremorSamples) } catch { }
        }
    }

    // MARK: - Workout metadata

    private func workoutMetadata(snapshots: [TremorSnapshot],
                                 type: String,
                                 efficacy: Double? = nil) -> [String: Any] {
        guard !snapshots.isEmpty else {
            return ["TremorCalm_StimulationType": type]
        }
        let detected  = snapshots.filter { $0.confidence >= 0.5 }
        let avgConf   = snapshots.map(\.confidence).avg
        let peakConf  = snapshots.map(\.confidence).max() ?? 0
        let avgHz     = detected.isEmpty ? 0.0 : detected.map(\.hz).avg
        let pctTremor = Double(detected.count) / Double(snapshots.count) * 100

        return [
            "TremorCalm_StimulationType": type,
            "TremorCalm_AvgConfidence":   String(format: "%.2f",  avgConf),
            "TremorCalm_PeakConfidence":  String(format: "%.2f",  peakConf),
            "TremorCalm_AvgTremorHz":     String(format: "%.1f",  avgHz),
            "TremorCalm_TremorPercent":   String(format: "%.0f%%", pctTremor),
        ].merging(efficacyMetadata(efficacy)) { _, new in new }
    }

    private func efficacyMetadata(_ efficacy: Double?) -> [String: Any] {
        guard let e = efficacy else { return [:] }
        return ["TremorCalm_Efficacy": String(format: "%.1f%%", e * 100)]
    }

    // MARK: - Tremor episodes → HKCategorySample

    private func tremorCategorySamples(snapshots: [TremorSnapshot]) -> [HKSample] {
        guard let tremorType = HKObjectType.categoryType(forIdentifier: tremorIdentifier),
              !snapshots.isEmpty
        else { return [] }

        let interval: TimeInterval = 30  // each snapshot represents 30 s
        var samples:  [HKSample]   = []
        var episode:  [TremorSnapshot] = []

        func flush() {
            guard !episode.isEmpty else { return }
            let eStart  = episode.first!.timestamp
            let eEnd    = episode.last!.timestamp.addingTimeInterval(interval)
            let avgConf = episode.map(\.confidence).avg
            let avgHz   = episode.map(\.hz).avg
            let sample  = HKCategorySample(
                type:     tremorType,
                value:    severityValue(for: avgConf),
                start:    eStart,
                end:      eEnd,
                metadata: ["TremorCalm_AvgHz": String(format: "%.1f", avgHz)]
            )
            samples.append(sample)
            episode.removeAll()
        }

        for snap in snapshots {
            if snap.confidence >= 0.5 { episode.append(snap) } else { flush() }
        }
        flush()

        return samples
    }
}

// MARK: - Helpers

private extension Array where Element == Double {
    var avg: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}
