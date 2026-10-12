//
//  SpokeApp.swift
//  Spoke
//
//  Created by Beck Orion on 8/27/26.
//

import SwiftUI
import SwiftData

@main
struct SpokeApp: App {
    @StateObject private var spotifyAuthentication = SpotifyAuthenticationStore()
    @State private var rideSession: RideSessionController
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            AppSettings.self,
            TrackedRide.self,
            RideRoutePoint.self,
            RideSoundtrackEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("--ui-testing")
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if modelConfiguration.isStoredInMemoryOnly,
               ProcessInfo.processInfo.arguments.contains("--ride-fixture") {
                try RideUITestFixture.insert(into: container.mainContext)
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        let rideSession = RideSessionController()
        // Restore location sessions at launch, even when iOS launches us in the background.
        rideSession.configure(modelContext: sharedModelContainer.mainContext)
        _rideSession = State(initialValue: rideSession)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(rideSession: rideSession)
                .environmentObject(spotifyAuthentication)
                .disablesKeyboardSafeArea()

        }
        .modelContainer(sharedModelContainer)
    }
}
