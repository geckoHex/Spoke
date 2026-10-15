import Foundation
import SwiftData

// The app and Live Activity intents must share both the context and the location session,
// including when iOS launches the app in the background to handle a button press.
@MainActor
enum RideSessionStore {
    static let modelContainer: ModelContainer = {
        let schema = Schema([
            AppSettings.self,
            TrackedRide.self,
            RideRoutePoint.self,
            RideSoundtrackEntry.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("--ui-testing")
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            if configuration.isStoredInMemoryOnly,
               ProcessInfo.processInfo.arguments.contains("--ride-fixture") {
                try RideUITestFixture.insert(into: container.mainContext)
            }
            if configuration.isStoredInMemoryOnly,
               ProcessInfo.processInfo.arguments.contains("--stats-fixture") {
                try RideUITestFixture.insertStats(into: container.mainContext)
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    static let controller: RideSessionController = {
        let controller = RideSessionController(liveActivity: RideLiveActivityController())
        controller.configure(modelContext: modelContainer.mainContext)
        return controller
    }()
}
