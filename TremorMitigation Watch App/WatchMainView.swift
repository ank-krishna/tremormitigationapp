//
//  WatchMainView.swift
//  TremorMitigation Watch App
//
//  Root tab container after onboarding: Home, History, Settings.
//

import SwiftUI

struct WatchMainView: View {
    var body: some View {
        TabView {
            WatchHomeView()
            WatchSettingsView()
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}
