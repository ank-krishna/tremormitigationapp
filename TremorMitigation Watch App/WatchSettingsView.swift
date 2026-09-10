//
//  WatchSettingsView.swift
//  TremorMitigation Watch App
//
//  Compact settings screen for Apple Watch.
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct WatchSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var stimulationService: StimulationService
    @EnvironmentObject var onboardingManager: OnboardingManager
    @StateObject private var hkManager = HealthKitManager.shared

    @State private var showResetProfileAlert    = false
    @State private var showResetOnboardingAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section("Profile") {
                    let profile = stimulationService.tremorProfile

                    LabeledContent("Sessions", value: "\(profile.sessionCount)")
                    LabeledContent("Observations", value: "\(profile.observationCount)")

                    if profile.isCalibrated {
                        LabeledContent(
                            "Dominant Hz",
                            value: String(format: "%.1f Hz", profile.dominantFrequency)
                        )
                    } else {
                        HStack {
                            Text("Calibrating…")
                            Spacer()
                            ProgressView(
                                value: Double(profile.observationCount),
                                total: Double(TremorProfile.calibrationThreshold)
                            )
                            .frame(width: 44)
                        }
                    }

                    Button("Reset profile", role: .destructive) {
                        showResetProfileAlert = true
                    }
                    .font(.system(size: 13))
                }

                // Tracking section
                Section("Tracking") {
                    Toggle(isOn: $settingsManager.enableEfficacyTracking) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Efficacy").font(.system(size: 12, weight: .medium))
                            Text("Measure tremor reduction")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(cobalt)
                }

                // Safety section
                Section("Safety") {
                    LabeledContent("Max session", value: "60 min")
                    LabeledContent("Rest between", value: "5 min")
                    LabeledContent("Daily limit", value: "\(settingsManager.dailySessionLimit) sessions")
                }

                // Health section
                Section("Health") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Health")
                            .font(.system(size: 12, weight: .medium))
                        Text(hkStatusText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    if hkManager.authStatus == .notDetermined || hkManager.authStatus == .denied {
                        Button("Connect Health") {
                            Task { await hkManager.requestAuthorization() }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(cobalt)
                    }
                }

                // About section
                Section("About") {
                    LabeledContent("App", value: "TremorCalm")
                    LabeledContent("Version", value: "1.0.0")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disclaimer")
                            .font(.system(size: 11, weight: .medium))
                        Text("Not a medical device. Consult your neurologist before use.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    Button("Replay onboarding") {
                        showResetOnboardingAlert = true
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Reset Tremor Profile?", isPresented: $showResetProfileAlert) {
            Button("Reset", role: .destructive) {
                Task { @MainActor in
                    stimulationService.resetTremorProfile()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All learned tremor data will be erased.")
        }
        .alert("Replay Onboarding?", isPresented: $showResetOnboardingAlert) {
            Button("Reset", role: .destructive) {
                onboardingManager.resetOnboarding()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Onboarding will show again on next launch.")
        }
    }

    private var hkStatusText: String {
        switch hkManager.authStatus {
        case .authorized:    return "Connected"
        case .denied:        return "Access denied"
        case .unavailable:   return "Not available"
        case .notDetermined: return "Not connected"
        }
    }
}
