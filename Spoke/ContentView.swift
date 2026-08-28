//
//  ContentView.swift
//  Spoke
//
//  Created by Beck Orion on 8/27/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView()
            }

            Tab("Ride", systemImage: "figure.outdoor.cycle", value: .ride) {
                RideView()
            }

            Tab(
                "History",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                value: .history
            ) {
                HistoryView()
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private enum AppTab: Hashable {
    case home
    case ride
    case history
    case settings
}

private struct HomeView: View {
    var body: some View {
        PlaceholderView(title: "Home")
    }
}

private struct RideView: View {
    var body: some View {
        PlaceholderView(title: "Ride")
    }
}

private struct HistoryView: View {
    var body: some View {
        PlaceholderView(title: "History")
    }
}

private struct SettingsView: View {
    var body: some View {
        PlaceholderView(title: "Settings")
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        NavigationStack {
            Color.black
                .ignoresSafeArea()
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
}
