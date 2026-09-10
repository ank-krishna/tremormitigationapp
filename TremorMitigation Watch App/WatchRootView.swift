//
//  WatchRootView.swift
//  TremorMitigation Watch App
//
//  Gate view: shows onboarding on first launch, main app thereafter.
//

import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager

    var body: some View {
        WatchMainView()
            .fullScreenCover(isPresented: .constant(!onboardingManager.hasCompletedOnboarding)) {
                OnboardingView()
            }
    }
}
