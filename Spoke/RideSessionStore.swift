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
            // A failed cache backfill must not prevent opening existing rides.
            // Reads can derive missing summaries from the unchanged route points.
            try? backfillRouteSummaries(in: container)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    static func backfillRouteSummaries(in container: ModelContainer) throws {
        var descriptor = FetchDescriptor<TrackedRide>(
            predicate: #Predicate { $0.routeSummaryPointCount == nil }
        )
        descriptor.fetchLimit = 100

        while true {
            // Release each batch's route objects before fetching the next one.
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let rides = try context.fetch(descriptor)
            guard !rides.isEmpty else { return }
            for ride in rides {
                ride.routeSummary = RideRouteSummary(points: ride.routePoints)
            }
            try context.save()
        }
    }

    static let controller: RideSessionController = {
        let controller = RideSessionController(liveActivity: RideLiveActivityController())
        controller.configure(modelContext: modelContainer.mainContext)
        return controller
    }()
}
