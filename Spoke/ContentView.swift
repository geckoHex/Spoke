//
//  ContentView.swift
//  Spoke
//
//  Created by Beck Orion on 8/27/26.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var storedSettings: [AppSettings]
    @State private var selectedTab: AppTab = .home
    @State private var highlightedRideID: PersistentIdentifier?
    @State private var completedRide: TrackedRide?
    @State private var rideSession = RideSessionController()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: .home) {
                HomeView(
                    settings: settings,
                    rideSession: rideSession,
                    onRideStarted: {
                        selectedTab = .ride
                    },
                    onEndRide: endRide
                )
            }

            Tab(AppTab.ride.title, systemImage: AppTab.ride.symbol, value: .ride) {
                RideView(settings: settings, rideSession: rideSession, onEndRide: endRide)
            }

            Tab(
                AppTab.history.title,
                systemImage: AppTab.history.symbol,
                value: .history
            ) {
                HistoryView(highlightedRideID: $highlightedRideID)
            }

            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: .settings) {
                SettingsView(settings: settings)
            }
        }
        .tabBarMinimizeBehavior(.never)
        .toolbarColorScheme(.dark, for: .tabBar)
        .foregroundStyle(SpokeStyle.text)
        .background(SpokeStyle.background)
        .preferredColorScheme(.dark)
        .tint(SpokeStyle.accent)
        .sheet(item: $completedRide) { ride in
            RideSummaryView(
                ride: ride,
                onDone: {
                    completedRide = nil
                    highlightedRideID = ride.persistentModelID
                    selectedTab = .history
                },
                onDiscard: {
                    guard rideSession.discardRide(ride) else { return }
                    completedRide = nil
                }
            )
        }
        .task {
            createSettingsIfNeeded()
            rideSession.configure(modelContext: modelContext)
            updateIdleTimer()
        }
        .onChange(of: scenePhase) {
            updateIdleTimer()
        }
        .onChange(of: shouldKeepScreenOn) {
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func endRide() {
        completedRide = rideSession.endRide()
    }

    private var settings: AppSettings? {
        storedSettings.first
    }

    private var shouldKeepScreenOn: Bool {
        settings?.keepScreenOn ?? true
    }

    private func createSettingsIfNeeded() {
        if let settings {
            if !settings.spotifyClientID.isEmpty || !settings.spotifyClientSecret.isEmpty
                || !settings.spotifyRefreshToken.isEmpty {
                settings.spotifyClientID = ""
                settings.spotifyClientSecret = ""
                settings.spotifyRefreshToken = ""
                try? modelContext.save()
            }
            return
        }

        let settings = AppSettings()
        modelContext.insert(settings)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(settings)
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            scenePhase == .active && shouldKeepScreenOn
    }
}

private enum AppTab: Hashable, CaseIterable {
    case home
    case ride
    case history
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .ride: "Ride"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .ride: "bicycle"
        case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .settings: "gear"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SpotifyAuthenticationStore())
        .modelContainer(
            for: [
                Item.self,
                AppSettings.self,
                TrackedRide.self,
                RideRoutePoint.self,
                RideSoundtrackEntry.self,
            ],
            inMemory: true
        )
}
