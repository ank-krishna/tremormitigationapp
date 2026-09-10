//
//  WatchHomeView.swift
//  TremorMitigation Watch App
//
//  Main home screen: live tremor status, profile calibration badge,
//  and a prominent "Start Session" button.
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct WatchHomeView: View {
    @EnvironmentObject var stimulationService: StimulationService
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var showSessionSetup = false
    @State private var showActiveSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {

                    // ── Tremor status card ──────────────────────────
                    TremorStatusCard(
                        detected:   stimulationService.tremorDetected,
                        hz:         stimulationService.tremorHz,
                        confidence: stimulationService.tremorScore
                    )

                    // ── Profile calibration badge ───────────────────
                    let profile = stimulationService.tremorProfile
                    if !profile.isCalibrated {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.dots.scatter")
                                .font(.system(size: 10))
                            Text("Learning: \(profile.observationCount)/\(TremorProfile.calibrationThreshold)")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(cobalt)
                            Text(String(format: "Profile: %.1f Hz", profile.dominantFrequency))
                                .font(.system(size: 10))
                                .foregroundStyle(cobalt)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cobalt.opacity(0.12), in: Capsule())
                    }

                    // ── Start Session ───────────────────────────────
                    Button {
                        showSessionSetup = true
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(cobalt)
                    .disabled(stimulationService.isActive)

                    // Last session
                    if let last = settingsManager.lastSessionDate {
                        Text("Last: \(last, style: .relative) ago")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("TremorCalm")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showSessionSetup) {
            WatchSessionSetupView()
        }
        .fullScreenCover(isPresented: $showActiveSession) {
            WatchActiveSessionView()
        }
        .onChange(of: stimulationService.isActive) { isActive in
            if isActive { showActiveSession = true }
        }
    }
}

// MARK: - Tremor status card

private struct TremorStatusCard: View {
    let detected:   Bool
    let hz:         Double
    let confidence: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // Pulsing indicator dot
                Circle()
                    .fill(detected ? Color.red : Color.green)
                    .frame(width: 8, height: 8)

                if detected {
                    Text(String(format: "%.1f Hz detected", hz))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                } else {
                    Text("No tremor")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(String(format: "%.0f%%", confidence * 100))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Confidence bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule()
                        .fill(detected ? Color.red : Color.green)
                        .frame(width: geo.size.width * max(0, min(confidence, 1)), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
