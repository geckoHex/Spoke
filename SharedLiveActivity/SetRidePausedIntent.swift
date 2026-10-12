import AppIntents
import Foundation

nonisolated struct SetRidePausedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Ride"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Ride")
    var rideID: String

    @Parameter(title: "Paused")
    var isPaused: Bool

    init() {}

    init(rideID: String, isPaused: Bool) {
        self.rideID = rideID
        self.isPaused = isPaused
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // LiveActivityIntent runs in the app process, using the same session as the UI.
        #if !SPOKE_WIDGET_EXTENSION
        try await RideSessionStore.controller.setPausedFromLiveActivity(
            rideID: rideID,
            isPaused: isPaused
        )
        #endif
        return .result()
    }
}
