import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hkManager = HealthKitManager.shared

    @State private var showingSessionHistory = false
    @State private var showingSafetyInfo     = false

    var body: some View {
        NavigationView {
            List {
                // Haptics
                Section {
                    Toggle(isOn: $settingsManager.enableHapticFeedback) {
                        settingsRowLabel(icon: "hand.raised.fill", iconColor: cobalt,
                                         title: "Haptic Feedback",
                                         subtitle: "Vibration during sessions")
                    }
                    .tint(cobalt)

                    Toggle(isOn: $settingsManager.autoPauseOnInactivity) {
                        settingsRowLabel(icon: "pause.circle.fill", iconColor: cobalt.opacity(0.7),
                                         title: "Auto-Pause",
                                         subtitle: "Pause after 60 s of inactivity")
                    }
                    .tint(cobalt)
                    Toggle(isOn: $settingsManager.enableEfficacyTracking) {
                        settingsRowLabel(icon: "chart.line.downtrend.xyaxis", iconColor: cobalt.opacity(0.7),
                                         title: "Efficacy Tracking",
                                         subtitle: "Measure tremor reduction per session")
                    }
                    .tint(cobalt)
                } header: {
                    Text("Feedback").foregroundColor(cobalt)
                }

                // Safety
                Section {
                    Toggle(isOn: $settingsManager.emergencyStopEnabled) {
                        settingsRowLabel(icon: "exclamationmark.shield.fill", iconColor: .red.opacity(0.8),
                                         title: "Emergency Stop",
                                         subtitle: "Long-press stop to end immediately")
                    }
                    .tint(cobalt)

                    settingsRow(icon: "clock.fill", iconColor: cobalt.opacity(0.7),
                                title: "Daily Limit",
                                subtitle: "\(settingsManager.dailySessionLimit) sessions · \(settingsManager.getTodaySessionCount()) today")

                    settingsRow(icon: "clock.arrow.circlepath", iconColor: cobalt.opacity(0.6),
                                title: "Rest Period",
                                subtitle: "5 minutes between sessions")

                    Button("Safety Info") { showingSafetyInfo = true }
                        .font(.system(size: 13))
                        .foregroundColor(cobalt)
                } header: {
                    Text("Safety").foregroundColor(cobalt)
                }

                // History
                Section {
                    Button(action: { showingSessionHistory = true }) {
                        settingsRow(icon: "chart.bar.fill", iconColor: cobalt,
                                    title: "Session History",
                                    subtitle: "\(settingsManager.sessionHistory.count) recorded")
                    }

                    if let last = settingsManager.lastSessionDate {
                        settingsRow(icon: "calendar", iconColor: cobalt.opacity(0.7),
                                    title: "Last Session",
                                    subtitle: nil) {
                            Text(last, style: .relative)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("History").foregroundColor(cobalt)
                }

                // Health
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(.red.opacity(0.8))
                            .font(.system(size: 16)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health").font(.system(size: 14, weight: .medium))
                            Text(healthStatusText).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        Spacer()
                        if hkManager.authStatus == .notDetermined || hkManager.authStatus == .denied {
                            Button("Connect") {
                                Task { await hkManager.requestAuthorization() }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(cobalt)
                        }
                    }
                } header: {
                    Text("Health").foregroundColor(cobalt)
                }

                // App info
                Section {
                    settingsRow(icon: "info.circle.fill", iconColor: cobalt.opacity(0.5),
                                title: "Version", subtitle: "1.0.0")
                    settingsRow(icon: "heart.fill", iconColor: .red.opacity(0.8),
                                title: "Medical Disclaimer",
                                subtitle: "Not a medical device. Consult your doctor.")
                } header: {
                    Text("App Info").foregroundColor(cobalt)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(cobalt)
                }
            }
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
                .environmentObject(settingsManager)
        }
        .alert("Safety Information", isPresented: $showingSafetyInfo) {
            Button("OK") { }
        } message: {
            Text("Sessions are limited to 1 hour with 5-minute rest periods. The daily limit is \(settingsManager.dailySessionLimit) sessions. Always consult your healthcare provider before use.")
        }
    }

    private var healthStatusText: String {
        switch hkManager.authStatus {
        case .authorized:     return "Connected — sessions logged to Health"
        case .denied:         return "Access denied — tap Connect to retry"
        case .unavailable:    return "Not available on this device"
        case .notDetermined:  return "Tap Connect to enable Health tracking"
        }
    }

    @ViewBuilder
    private func settingsRowLabel(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 16)).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func settingsRow<Accessory: View>(
        icon: String, iconColor: Color, title: String, subtitle: String?,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 16)).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                if let s = subtitle { Text(s).font(.system(size: 12)).foregroundColor(.secondary) }
            }
            Spacer()
            accessory()
        }
    }
}

// MARK: - Session History

struct SessionHistoryView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var showClearAlert = false

    var body: some View {
        NavigationView {
            Group {
                if settingsManager.sessionHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 32))
                            .foregroundColor(cobalt.opacity(0.4))
                        Text("No Sessions Yet")
                            .font(.system(size: 16, weight: .medium))
                        Text("Your session history will appear here after your first session.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(settingsManager.sessionHistory) { record in
                        SessionHistoryRow(record: record)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Session History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(cobalt)
                }
                if !settingsManager.sessionHistory.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear") { showClearAlert = true }.foregroundColor(.red)
                    }
                }
            }
        }
        .alert("Clear History?", isPresented: $showClearAlert) {
            Button("Clear All", role: .destructive) { settingsManager.clearSessionHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct SessionHistoryRow: View {
    let record: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName(for: record.stimulationType))
                    .foregroundColor(cobalt).font(.system(size: 14))
                Text(record.stimulationType.capitalized)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(record.startTime, style: .date)
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            HStack {
                Text("\(record.intensity.capitalized) · \(record.formattedDuration)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                if let efficacyStr = record.formattedEfficacy {
                    Text(efficacyStr)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(record.efficacy ?? 0 > 0 ? .green : .orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((record.efficacy ?? 0 > 0 ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                }
                Spacer()
                if record.wasCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundColor(cobalt)
                        .labelStyle(.iconOnly)
                } else if record.userStopped {
                    Label("Stopped", systemImage: "stop.circle.fill")
                        .font(.system(size: 11)).foregroundColor(.orange)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "electrical": return "bolt.fill"
        case "combined":   return "waveform.path.ecg.rectangle"
        default:           return "waveform.path.ecg"
        }
    }
}

#Preview {
    SettingsView().environmentObject(SettingsManager.shared)
}
