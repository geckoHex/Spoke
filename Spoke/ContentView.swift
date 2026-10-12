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
    @State private var rideStartSource: RideStartButton?
    @State private var rideStartSound = RideAudioPlayer(
        resourceURL: Bundle.main.url(forResource: "ride-start", withExtension: "mp3", subdirectory: "sounds")
    )
    @State private var rideEndSound = RideAudioPlayer(
        resourceURL: Bundle.main.url(forResource: "ride-end", withExtension: "mp3", subdirectory: "sounds")
    )
    let rideSession: RideSessionController

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: .home) {
                HomeView(
                    settings: settings,
                    rideSession: rideSession,
                    onStartRide: { startRide(from: .home) },
                    onShowRide: {
                        selectedTab = .ride
                    },
                    onEndRide: endRide
                )
            }

            Tab(AppTab.ride.title, systemImage: AppTab.ride.symbol, value: .ride) {
                RideView(
                    settings: settings,
                    rideSession: rideSession,
                    onStartRide: { startRide(from: .ride) },
                    onEndRide: endRide
                )
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
        .foregroundStyle(SpokeStyle.text)
        .background(SpokeStyle.background)
        .preferredColorScheme(.dark)
        .tint(SpokeStyle.accent)
        .allowsHitTesting(rideStartSource == nil)
        .accessibilityHidden(rideStartSource != nil)
        .overlayPreferenceValue(RideStartButtonPreference.self) { anchors in
            GeometryReader { proxy in
                if let rideStartSource {
                    RideStartTransition(
                        sourceFrame: anchors[rideStartSource].map { proxy[$0] } ?? .zero,
                        destinationFrame: anchors[.pause].map { proxy[$0] },
                        onCovered: {
                            guard rideSession.startRide() != nil else { return false }
                            selectedTab = .ride
                            return true
                        },
                        onFinished: { self.rideStartSource = nil }
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(rideStartSource != nil)
        }
        .sheet(item: $completedRide) { ride in
            RideSummaryView(
                ride: ride,
                onDone: {
                    completedRide = nil
                    highlightedRideID = ride.persistentModelID
                    selectedTab = .history
                },
                onDiscard: {
                    guard rideSession.discardRide(ride) else { return false }
                    completedRide = nil
                    return true
                }
            )
        }
        .alert("Ride couldn’t be updated", isPresented: Binding(
            get: { rideSession.errorMessage != nil },
            set: { if !$0 { rideSession.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { rideSession.errorMessage = nil }
        } message: {
            Text(rideSession.errorMessage ?? "Please try again.")
        }
        .task {
            createSettingsIfNeeded()
            rideSession.resumeLocationUpdatesIfNeeded()
            updateIdleTimer()
        }
        .task(id: soundEffectsEnabled) {
            guard !soundEffectsEnabled else { return }
            await rideStartSound.stop()
            await rideEndSound.stop()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { rideSession.resumeLocationUpdatesIfNeeded() }
            if scenePhase == .background { rideStartSource = nil }
            updateIdleTimer()
        }
        .onChange(of: shouldKeepScreenOn) {
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func startRide(from source: RideStartButton) {
        rideStartSource = source
        Task {
            guard soundEffectsEnabled else { return }
            await rideStartSound.play()
        }
    }

    private func endRide() {
        completedRide = rideSession.endRide()
        guard completedRide != nil else { return }
        Task {
            await rideStartSound.stop()
            guard soundEffectsEnabled else { return }
            await rideEndSound.play()
        }
    }

    private var settings: AppSettings? {
        storedSettings.first
    }

    private var soundEffectsEnabled: Bool {
        settings?.soundEffectsEnabled ?? true
    }

    private var shouldKeepScreenOn: Bool {
        (settings?.keepScreenOn ?? true) && rideSession.activeRide != nil
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

private enum AppTab: Hashable {
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
        case .home: "house"
        case .ride: "bicycle"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}

#Preview {
    ContentView(rideSession: RideSessionController())
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
