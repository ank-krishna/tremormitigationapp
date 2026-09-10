import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct SessionView: View {
    @EnvironmentObject var stimulationService: StimulationService
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: StimulationType = .vibration
    @State private var selectedIntensity: StimulationIntensity = .medium
    @State private var selectedDuration: SessionDuration = .fifteenMinutes
    @State private var isStartingSession = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Text("New Session")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(cobalt)
                        Text("Choose your relief settings")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)

                    sectionCard(title: "Stimulation Type") {
                        HStack(spacing: 8) {
                            ForEach(StimulationType.allCases, id: \.self) { type in
                                StimulationTypeButton(
                                    type: type,
                                    isSelected: selectedType == type,
                                    action: { selectedType = type }
                                )
                            }
                        }
                    }

                    sectionCard(title: "Intensity") {
                        HStack(spacing: 8) {
                            ForEach(StimulationIntensity.allCases, id: \.self) { intensity in
                                IntensityButton(
                                    intensity: intensity,
                                    isSelected: selectedIntensity == intensity,
                                    action: { selectedIntensity = intensity }
                                )
                            }
                        }
                    }

                    sectionCard(title: "Duration") {
                        HStack(spacing: 8) {
                            ForEach(SessionDuration.allCases, id: \.self) { duration in
                                DurationButton(
                                    duration: duration,
                                    isSelected: selectedDuration == duration,
                                    action: { selectedDuration = duration }
                                )
                            }
                        }
                    }

                    // Start Button
                    Button(action: startSession) {
                        HStack(spacing: 8) {
                            if isStartingSession {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15))
                            }
                            Text(isStartingSession ? "Starting..." : "Start Session")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isStartingSession ? Color.gray : cobalt)
                        )
                    }
                    .disabled(isStartingSession)
                    .buttonStyle(PlainButtonStyle())
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Session Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(cobalt)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(cobalt)
                .padding(.horizontal, 4)
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: cobalt.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }

    private func startSession() {
        isStartingSession = true

        let settings = StimulationSettings(
            stimulationType: selectedType,
            intensity: selectedIntensity,
            sessionDuration: selectedDuration,
            lastSessionDate: settingsManager.lastSessionDate
        )

        Task {
            do {
                try await stimulationService.startStimulation(with: settings)
                await MainActor.run {
                    settingsManager.lastSessionDate = Date()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isStartingSession = false
                }
            }
        }
    }
}

// MARK: - Custom Buttons

struct StimulationTypeButton: View {
    let type: StimulationType
    let isSelected: Bool
    let action: () -> Void

    private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.iconName)
                    .font(.system(size: 20))
                Text(type.displayName)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : cobalt)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? cobalt : cobalt.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(cobalt.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IntensityButton: View {
    let intensity: StimulationIntensity
    let isSelected: Bool
    let action: () -> Void

    private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

    var body: some View {
        Button(action: action) {
            Text(intensity.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : cobalt)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? cobalt : cobalt.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(cobalt.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DurationButton: View {
    let duration: SessionDuration
    let isSelected: Bool
    let action: () -> Void

    private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

    var body: some View {
        Button(action: action) {
            Text(duration.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : cobalt)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? cobalt : cobalt.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(cobalt.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SessionView()
        .environmentObject(StimulationService.shared)
        .environmentObject(SettingsManager())
}
