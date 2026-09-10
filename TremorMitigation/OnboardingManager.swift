//
//  OnboardingManager.swift
//  TremorMitigationApp
//
//  Tracks first-launch state and persists it across app restarts.
//

import Foundation

final class OnboardingManager: ObservableObject {

    static let shared = OnboardingManager()

    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var hasAcknowledgedDisclaimer: Bool

    private let onboardingKey  = "com.tremorapp.onboardingComplete.v1"
    private let disclaimerKey  = "com.tremorapp.disclaimerAcknowledged.v1"

    private init() {
        hasCompletedOnboarding   = UserDefaults.standard.bool(forKey: "com.tremorapp.onboardingComplete.v1")
        hasAcknowledgedDisclaimer = UserDefaults.standard.bool(forKey: "com.tremorapp.disclaimerAcknowledged.v1")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    func acknowledgeDisclaimer() {
        hasAcknowledgedDisclaimer = true
        UserDefaults.standard.set(true, forKey: disclaimerKey)
    }

    /// For development / testing: resets onboarding so it shows again on next launch.
    func resetOnboarding() {
        hasCompletedOnboarding    = false
        hasAcknowledgedDisclaimer = false
        UserDefaults.standard.removeObject(forKey: onboardingKey)
        UserDefaults.standard.removeObject(forKey: disclaimerKey)
    }
}
