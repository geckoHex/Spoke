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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            AppSettings.self,
            TrackedRide.self,
            RideRoutePoint.self,
            RideSoundtrackEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .modelContainer(sharedModelContainer)
    }
}
