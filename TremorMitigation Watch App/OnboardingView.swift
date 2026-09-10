//
//  OnboardingView.swift
//  TremorMitigation Watch App
//
//  4-page first-launch onboarding flow optimised for the watch screen.
//  Pages are swiped horizontally; a "Get Started" button on the last page
//  marks onboarding complete and dismisses this cover.
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct OnboardingView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager

    @State private var currentPage = 0
    private let totalPages = 4

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage()
                .tag(0)
            HowItWorksPage()
                .tag(1)
            WearGuidePage()
                .tag(2)
            DisclaimerPage(onFinish: {
                onboardingManager.acknowledgeDisclaimer()
                onboardingManager.completeOnboarding()
                Task { await HealthKitManager.shared.requestAuthorization() }
            })
            .tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(cobalt)

            Text("TremorCalm")
                .font(.system(size: 18, weight: .bold))

            Text("Adaptive relief for\nParkinson's tremor")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Swipe to continue")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Page 2: How it works

private struct HowItWorksPage: View {
    private let steps: [(String, String)] = [
        ("waveform.path", "Detects your tremor in real time using the watch sensor"),
        ("brain",         "Learns your unique pattern session by session"),
        ("hand.raised.fill", "Delivers haptic pulses to help reduce tremor"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(steps, id: \.0) { icon, text in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(cobalt)
                        .frame(width: 18)
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Page 3: Wear guide

private struct WearGuidePage: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "applewatch.watchface")
                .font(.system(size: 32))
                .foregroundStyle(cobalt)

            Text("Wear it snugly")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 5) {
                GuideRow(icon: "hand.raised",    text: "Place on your most affected wrist")
                GuideRow(icon: "lock.fill",      text: "Strap should be firm, not tight")
                GuideRow(icon: "battery.100",    text: "Keep battery above 20% during sessions")
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct GuideRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(cobalt)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 4: Disclaimer + finish

private struct DisclaimerPage: View {
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red.opacity(0.8))

                Text("Medical notice")
                    .font(.system(size: 13, weight: .semibold))

                Text("TremorCalm is a wellness aid, not a medical device. Always consult your neurologist or movement disorder specialist before use. Do not replace prescribed medication or therapy.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onFinish) {
                    Text("I understand — Get Started")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(cobalt)
            }
            .padding(.horizontal, 8)
        }
    }
}
