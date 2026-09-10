//
//  IOSOnboardingView.swift
//  TremorMitigation (iOS)
//
//  First-launch onboarding for iPhone. Uses a page-style TabView matching
//  the watchOS flow but with iOS-native sizing and navigation.
//

import SwiftUI

private let cobalt = Color(red: 0.0, green: 0.278, blue: 0.671)

struct IOSOnboardingView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                IOSWelcomePage().tag(0)
                IOSHowItWorksPage().tag(1)
                IOSWearGuidePage().tag(2)
                IOSDisclaimerPage(onFinish: {
                    onboardingManager.acknowledgeDisclaimer()
                    onboardingManager.completeOnboarding()
                    Task { await HealthKitManager.shared.requestAuthorization() }
                }).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Skip / Next controls
            if page < 3 {
                HStack {
                    Button("Skip") {
                        page = 3
                    }
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)

                    Spacer()

                    Button("Next") {
                        withAnimation { page += 1 }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(cobalt)
                    .padding(.trailing, 32)
                }
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Page 1: Welcome

private struct IOSWelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(cobalt)
            VStack(spacing: 8) {
                Text("TremorCalm")
                    .font(.system(size: 34, weight: .bold))
                Text("Adaptive relief for Parkinson's tremor")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Text("Swipe to learn more")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 80)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Page 2: How it works

private struct IOSHowItWorksPage: View {
    private let steps: [(String, String, String)] = [
        ("waveform.path",       "Detects",     "Real-time tremor analysis using your watch's motion sensor at 100 Hz"),
        ("brain",               "Learns",      "Builds a personalised tremor profile session over session using on-device ML"),
        ("hand.raised.fill",    "Relieves",    "Delivers adaptive haptic stimulation synchronised to your tremor frequency"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("How TremorCalm works")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 60)

            ForEach(steps, id: \.0) { icon, heading, detail in
                HStack(alignment: .top, spacing: 20) {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(cobalt)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(heading)
                            .font(.system(size: 17, weight: .semibold))
                        Text(detail)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
    }
}

// MARK: - Page 3: Wear guide

private struct IOSWearGuidePage: View {
    private let tips: [(String, String, String)] = [
        ("hand.raised",    "Affected wrist",    "Wear on the wrist most affected by tremor for best detection accuracy"),
        ("lock.fill",      "Snug fit",           "Strap should be firm enough that the watch doesn't shift — not painfully tight"),
        ("battery.100",    "Keep charged",       "Maintain above 20% battery during sessions for uninterrupted monitoring"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Wearing your watch")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 60)

            ForEach(tips, id: \.0) { icon, heading, detail in
                HStack(alignment: .top, spacing: 20) {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(cobalt)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(heading).font(.system(size: 17, weight: .semibold))
                        Text(detail).font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
    }
}

// MARK: - Page 4: Disclaimer + finish

private struct IOSDisclaimerPage: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red.opacity(0.85))

            Text("Medical notice")
                .font(.system(size: 28, weight: .bold))

            Text("TremorCalm is a wellness aid, not a certified medical device. It is not a replacement for prescribed medication, physical therapy, or neurological care.\n\nAlways consult your neurologist or movement disorder specialist before starting or changing any tremor management approach.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer()

            Button(action: onFinish) {
                Text("I understand — Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(cobalt, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 24)
    }
}
