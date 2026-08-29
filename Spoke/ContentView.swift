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
    @State private var rideSession = RideSessionController()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(
                    settings: settings,
                    rideSession: rideSession,
                    onRideStarted: {
                        selectedTab = .ride
                    },
                    onRideSummaryDone: { ride in
                        highlightedRideID = ride.persistentModelID
                        selectedTab = .history
                    }
                )
            }

            Tab("HUD", systemImage: "gauge.open.with.lines.needle.33percent", value: .ride) {
                RideView(settings: settings, rideSession: rideSession)
            }

            Tab(
                "History",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                value: .history
            ) {
                HistoryView(highlightedRideID: $highlightedRideID)
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView(settings: settings)
            }
        }
        .preferredColorScheme(.dark)
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

    private var settings: AppSettings? {
        storedSettings.first
    }

    private var shouldKeepScreenOn: Bool {
        settings?.keepScreenOn ?? true
    }

    private func createSettingsIfNeeded() {
        guard settings == nil else { return }

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

private enum AppTab: Hashable {
    case home
    case ride
    case history
    case settings
}

#Preview {
    ContentView()
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
