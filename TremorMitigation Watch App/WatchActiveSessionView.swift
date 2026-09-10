//
//  WatchActiveSessionView.swift
//  TremorMitigation Watch App
//
//  Live session screen optimised for Apple Watch.
//
//  Layout
//  ──────
//  • Large countdown timer (centre)
//  • Tremor confidence ring
//  • Hz reading + filter-active badge
//  • Pause / Stop buttons
//  • Digital Crown → adjust haptic intensity in real time
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct WatchActiveSessionView: View {
    @EnvironmentObject var stimulationService: StimulationService
    @Environment(\.dismiss) private var dismiss

    @State private var isPaused   = false
    @State private var showStop   = false

    // Digital Crown — adjusts a local intensity multiplier shown in UI
    @State private var crownValue: Double = 0.5
    @FocusState private var crownFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // Background ring showing tremor confidence
                ConfidenceRing(confidence: stimulationService.tremorScore)
                    .padding(4)

                VStack(spacing: 4) {
                    // Session status badge
                    Text(isPaused ? "Paused" : "Active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isPaused ? .orange : cobalt)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (isPaused ? Color.orange : cobalt).opacity(0.15),
                            in: Capsule()
                        )

                    // Countdown
                    Text(timeString(stimulationService.remainingTime))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(cobalt)

                    // Tremor readout
                    if stimulationService.tremorDetected {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text(String(format: "%.1f Hz", stimulationService.tremorHz))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                            // Filter active badge
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 9))
                                .foregroundStyle(cobalt)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("No tremor")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
                    }

                    // Progress bar
                    if let session = stimulationService.currentSession {
                        let total    = session.settings.sessionDuration.durationInSeconds
                        let progress = 1.0 - (stimulationService.remainingTime / total)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary).frame(height: 3)
                                Capsule()
                                    .fill(cobalt)
                                    .frame(width: geo.size.width * max(0, min(progress, 1)),
                                           height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 16)
                    }

                    // Efficacy + intensity
                    HStack(spacing: 8) {
                        if let eff = stimulationService.liveEfficacy {
                            let reduced = eff > 0
                            Text(String(format: "%@%.0f%%", reduced ? "↓" : "↑", abs(eff) * 100))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(reduced ? .green : .orange)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "digitalcrown.horizontal.press")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(String(format: "%.0f%%", crownValue * 100))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Controls
                    HStack(spacing: 16) {
                        // Pause / Resume
                        Button {
                            togglePause()
                        } label: {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.bordered)
                        .tint(cobalt)

                        // Stop
                        Button {
                            showStop = true
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.horizontal, 8)
            }
            // Digital Crown controls intensity
            .focusable()
            .digitalCrownRotation(
                $crownValue,
                from: 0.0, through: 1.0,
                by: 0.05,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .navigationBarHidden(true)
        }
        .alert("Stop Session?", isPresented: $showStop) {
            Button("Stop", role: .destructive) { stopSession() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Progress will be saved.")
        }
        .onReceive(stimulationService.$isActive) { active in
            if !active { dismiss() }
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

    private func timeString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Confidence ring

private struct ConfidenceRing: View {
    let confidence: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0, min(confidence, 1)))
                .stroke(
                    confidence > 0.5 ? Color.red : Color.green,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: confidence)
        }
    }
}
