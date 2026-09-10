//
//  WatchSessionSetupView.swift
//  TremorMitigation Watch App
//
//  Compact session configuration: duration + intensity, then start.
//  Uses watchOS List pickers that navigate inline — no nested sheets.
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct WatchSessionSetupView: View {
    @EnvironmentObject var stimulationService: StimulationService
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var duration:   SessionDuration      = .tenMinutes
    @State private var intensity:  StimulationIntensity  = .medium
    @State private var stimType:   StimulationType       = .vibration
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Stimulation type picker
                Picker("Type", selection: $stimType) {
                    ForEach(StimulationType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }

                // Duration picker
                Picker("Duration", selection: $duration) {
                    ForEach(SessionDuration.allCases, id: \.self) { d in
                        Text(d.displayName).tag(d)
                    }
                }

                // Intensity picker
                Picker("Intensity", selection: $intensity) {
                    ForEach(StimulationIntensity.allCases, id: \.self) { i in
                        Text(i.displayName).tag(i)
                    }
                }

                // Start button
                Button {
                    startSession()
                } label: {
                    HStack {
                        if isStarting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isStarting ? "Starting…" : "Start")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(isStarting)
                .listRowBackground(cobalt)
                .foregroundStyle(.white)

                // Error message
                if let msg = errorMessage {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startSession() {
        isStarting = true
        errorMessage = nil

        let settings = StimulationSettings(
            stimulationType: stimType,
            intensity: intensity,
            sessionDuration: duration,
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
                    isStarting = false
                }
            }
        }
    }
}
