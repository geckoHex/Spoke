import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct RideSaveFailureTests {
    @Test func failedRideActionsPreserveTheRideAndCanBeRetried() throws {
        let schema = Schema([TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        var shouldFail = true
        let controller = RideSessionController { context in
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        controller.configure(modelContext: context)

        #expect(controller.startRide() == nil)
        #expect(controller.activeRide == nil)
        #expect(controller.errorMessage != nil)
        shouldFail = false
        let ride = try #require(controller.startRide())
        #expect(controller.errorMessage == nil)

        shouldFail = true
        controller.togglePause()
        #expect(!ride.isPaused)
        #expect(controller.errorMessage != nil)
        shouldFail = false
        controller.togglePause()
        #expect(ride.isPaused)

        shouldFail = true
        controller.togglePause()
        #expect(ride.isPaused)
        #expect(controller.errorMessage != nil)
        #expect(controller.endRide() == nil)
        #expect(ride.endedAt == nil)
        #expect(ride.isPaused)
        #expect(controller.activeRide === ride)

        shouldFail = false
        #expect(controller.endRide() === ride)
        #expect(controller.errorMessage == nil)
        shouldFail = true
        #expect(!controller.discardRide(ride))
        #expect(try context.fetchCount(FetchDescriptor<TrackedRide>()) == 1)
        shouldFail = false
        #expect(controller.discardRide(ride))
        #expect(try context.fetchCount(FetchDescriptor<TrackedRide>()) == 0)
    }
}
