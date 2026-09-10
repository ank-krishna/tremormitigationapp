//
//  ContentView.swift
//  TremorMitigationApp
//
//  Created by Anika Doddamane on 8/5/25.
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct ContentView: View {
    @EnvironmentObject var stimulationService: StimulationService
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var onboardingManager: OnboardingManager

    @State private var showSessionView = false
    @State private var showActiveSession = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            cobalt.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.trailing, 24)
                    .padding(.top, 16)
                }

                Spacer()

                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)

                VStack(spacing: 6) {
                    Text("Tremor Relief")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Adaptive stimulation for\nParkinson's tremor")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button(action: { showSessionView = true }) {
                    Text("Start Session")
                        .font(.headline)
                        .foregroundColor(cobalt)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSessionView) {
            SessionView()
                .environmentObject(stimulationService)
                .environmentObject(settingsManager)
        }
        .sheet(isPresented: $showActiveSession) {
            ActiveSessionView()
                .environmentObject(stimulationService)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settingsManager)
        }
        // Show active session sheet whenever a session starts
        .onChange(of: stimulationService.isActive) { isActive in
            if isActive { showActiveSession = true }
        }
        // Show onboarding on first launch
        .fullScreenCover(isPresented: .constant(!onboardingManager.hasCompletedOnboarding)) {
            IOSOnboardingView()
                .environmentObject(onboardingManager)
        }
    }
}
