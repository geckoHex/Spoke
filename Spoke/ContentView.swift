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
        VStack(spacing: 0) {
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
                    .toolbar(.hidden, for: .tabBar)
                }

                Tab(AppTab.ride.title, systemImage: AppTab.ride.symbol, value: .ride) {
                    RideView(settings: settings, rideSession: rideSession, onEndRide: endRide)
                        .toolbar(.hidden, for: .tabBar)
                }

                Tab(
                    AppTab.history.title,
                    systemImage: AppTab.history.symbol,
                    value: .history
                ) {
                    HistoryView(highlightedRideID: $highlightedRideID)
                        .toolbar(.hidden, for: .tabBar)
                }

                Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: .settings) {
                    SettingsView(settings: settings)
                        .toolbar(.hidden, for: .tabBar)
                }
            }

            tabBar
        }
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
        .fullScreenCover(isPresented: Binding(
            get: { rideSession.emergencyCheckIn.isPresented },
            set: { if !$0 { rideSession.emergencyCheckIn.dismiss(at: .now) } }
        )) {
            RideEmergencyCheckInView {
                rideSession.emergencyCheckIn.dismiss(at: .now)
            }
        }
        .task {
            while !Task.isCancelled {
                if let ride = rideSession.activeRide, !ride.isPaused {
                    rideSession.emergencyCheckIn.evaluate(
                        at: .now,
                        timeoutMinutes: settings?.emergencyCheckInMinutes ?? 3
                    )
                }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
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
        .onChange(of: rideSession.emergencyCheckIn.isPresented) {
            updateIdleTimer()
        }
        .onDisappear {
            if !rideSession.emergencyCheckIn.isPresented {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? SpokeStyle.text : SpokeStyle.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(SpokeStyle.background)
        .overlay(alignment: .top) {
            Rectangle().fill(SpokeStyle.separator).frame(height: 0.5)
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
            scenePhase == .active && (shouldKeepScreenOn || rideSession.emergencyCheckIn.isPresented)
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
