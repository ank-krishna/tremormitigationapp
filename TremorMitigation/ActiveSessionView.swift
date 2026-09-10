import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct ActiveSessionView: View {
    @EnvironmentObject var stimulationService: StimulationService
    @Environment(\.dismiss) private var dismiss

    @State private var showingStopConfirmation = false
    @State private var isPaused = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top header band
                cobalt
                    .frame(height: 6)

                VStack(spacing: 18) {
                    // Session type + icon
                    if let session = stimulationService.currentSession {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(cobalt.opacity(0.1))
                                    .frame(width: 68, height: 68)
                                Image(systemName: session.settings.stimulationType.iconName)
                                    .font(.system(size: 30))
                                    .foregroundColor(cobalt)
                            }

                            Text(session.settings.stimulationType.displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(cobalt)
                            Text(session.settings.intensity.displayName + " intensity")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                    }

                    // Timer
                    VStack(spacing: 2) {
                        Text(timeString(from: stimulationService.remainingTime))
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(cobalt)
                        Text("remaining")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    // Progress bar
                    if let session = stimulationService.currentSession {
                        let progress = 1.0 - (stimulationService.remainingTime / session.settings.sessionDuration.durationInSeconds)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(cobalt.opacity(0.15))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(cobalt)
                                    .frame(width: geo.size.width * progress, height: 8)
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal, 24)
                    }

                    // Tremor status card
                    VStack(spacing: 8) {
                        // Detection row — confidence meter
                        HStack(spacing: 8) {
                            Circle()
                                .fill(stimulationService.tremorDetected ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                            if stimulationService.tremorDetected {
                                Text(String(format: "Tremor %.1f Hz", stimulationService.tremorHz))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                            } else {
                                Text("No tremor detected")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", stimulationService.tremorScore * 100))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(stimulationService.tremorDetected ? .red : .secondary)
                        }

                        // Confidence bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(stimulationService.tremorDetected ? Color.red : Color.green)
                                    .frame(width: geo.size.width * stimulationService.tremorScore, height: 5)
                            }
                        }
                        .frame(height: 5)

                        // Filter status + learned profile
                        HStack(spacing: 6) {
                            if stimulationService.tremorDetected {
                                Label("Filter active", systemImage: "waveform.path.ecg")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(cobalt)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(cobalt.opacity(0.12), in: Capsule())
                            }
                            if let eff = stimulationService.liveEfficacy {
                                let reduced = eff > 0
                                Text(String(format: "%@%.0f%%", reduced ? "↓" : "↑", abs(eff) * 100))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(reduced ? .green : .orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((reduced ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                            }
                            Spacer()
                            let profile = stimulationService.tremorProfile
                            if profile.isCalibrated {
                                Text(String(format: "Profile: %.1f Hz · %d sessions",
                                            profile.dominantFrequency, profile.sessionCount))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Learning \(profile.observationCount)/\(TremorProfile.calibrationThreshold)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(cobalt.opacity(0.06))
                    )
                    .padding(.horizontal, 24)

                    Spacer()

                    // Status label
                    Text(isPaused ? "Session Paused" : "Session Active")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isPaused ? .orange : cobalt)

                    // Controls
                    HStack(spacing: 24) {
                        // Pause / Resume
                        Button(action: togglePause) {
                            VStack(spacing: 4) {
                                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(cobalt))
                                Text(isPaused ? "Resume" : "Pause")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Stop
                        Button(action: { showingStopConfirmation = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(Color.red.opacity(0.85)))
                                Text("Stop")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .alert("Stop Session", isPresented: $showingStopConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Stop", role: .destructive) { stopSession() }
        } message: {
            Text("Are you sure you want to stop the current session?")
        }
        .onReceive(stimulationService.$isActive) { isActive in
            if !isActive { dismiss() }
        }
    }

    private func togglePause() {
        Task {
            if isPaused {
                await stimulationService.resumeStimulation()
                await MainActor.run { isPaused = false }
            } else {
                await stimulationService.pauseStimulation()
                await MainActor.run { isPaused = true }
            }
        }
    }

    private func stopSession() {
        Task { await stimulationService.stopStimulation() }
    }

    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ActiveSessionView()
        .environmentObject(StimulationService.shared)
}
