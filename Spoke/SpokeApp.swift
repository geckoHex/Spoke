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

    init() {
        // Restore location sessions at launch, even when iOS launches us in the background.
        _rideSession = State(initialValue: RideSessionStore.controller)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(rideSession: rideSession)
                .environmentObject(spotifyAuthentication)
                .disablesKeyboardSafeArea()

        }
        .modelContainer(RideSessionStore.modelContainer)
    }
}
