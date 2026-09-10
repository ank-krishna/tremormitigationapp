//
//  TremorMitigationApp.swift
//  TremorMitigation  /  TremorMitigation Watch App
//
//  Shared app entry point.  Platform-specific root views are selected at
//  compile time so each target gets the right UI without code duplication.
//

import SwiftUI
import HealthKit

@main
struct TremorMitigationWatchApp: App {
    @StateObject private var stimulationService = StimulationService.shared
    @StateObject private var settingsManager    = SettingsManager.shared
    @StateObject private var onboardingManager  = OnboardingManager.shared

    var body: some Scene {
        WindowGroup {
#if os(watchOS)
            WatchRootView()
                .environmentObject(stimulationService)
                .environmentObject(settingsManager)
                .environmentObject(onboardingManager)
#else
            ContentView()
                .environmentObject(stimulationService)
                .environmentObject(settingsManager)
                .environmentObject(onboardingManager)
#endif
        }
    }
}
