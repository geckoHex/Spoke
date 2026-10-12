import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct BackgroundRideTrackingTests {
    @Test func delayedLocationsAreSavedWithoutShowingStaleSpeed() async throws {
        let container = try makeContainer()
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)
        let start = Date.now.addingTimeInterval(-120)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        defer { controller.endRide() }

        let first = sample(at: start.addingTimeInterval(10))
        let second = sample(at: start.addingTimeInterval(15))
        controller.recordLocation(first)
        controller.recordLocation(second)
        controller.recordLocation(first)

        #expect(ride.routePoints.count == 2)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RideRoutePoint>()) == 2)
        #expect(ride.routePoints.map(\.recordedAt).sorted() == [first.timestamp, second.timestamp])

        let speed = await RideSpeedProcessor().process([second], now: .now)
        #expect(speed.speedInMilesPerHour == nil)
        #expect(speed.mapLocation == nil)
    }

    @Test func pauseResumeAndEndBoundLocationRecording() throws {
        let container = try makeContainer()
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)
        #expect(!controller.isTrackingLocation)
        let start = Date.now.addingTimeInterval(-120)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        #expect(controller.isTrackingLocation)

        controller.recordLocation(sample(at: start.addingTimeInterval(5)))
        controller.togglePause(at: start.addingTimeInterval(10))
        #expect(!controller.isTrackingLocation)
        controller.resumeLocationUpdatesIfNeeded()
        #expect(!controller.isTrackingLocation)
        controller.recordLocation(sample(at: start.addingTimeInterval(15)))
        #expect(ride.routePoints.count == 1)

        controller.togglePause(at: start.addingTimeInterval(20))
        #expect(controller.isTrackingLocation)
        controller.recordLocation(sample(at: start.addingTimeInterval(15)))
        controller.recordLocation(sample(at: start.addingTimeInterval(25)))
        #expect(ride.routePoints.count == 2)

        controller.endRide(at: start.addingTimeInterval(30))
        #expect(!controller.isTrackingLocation)
        controller.resumeLocationUpdatesIfNeeded()
        controller.recordLocation(sample(at: start.addingTimeInterval(35)))
        #expect(!controller.isTrackingLocation)
        #expect(ride.routePoints.count == 2)
    }

    @Test func restoringRideRetainsRecordingBoundaryAndRejectsInvalidPoints() throws {
        let container = try makeContainer()
        let start = Date.now.addingTimeInterval(-120)
        let ride = TrackedRide(startedAt: start)
        ride.startAddress = "Test start"
        ride.pause(at: start.addingTimeInterval(10))
        ride.resume(at: start.addingTimeInterval(20))
        container.mainContext.insert(ride)
        try container.mainContext.save()

        let restoredContext = ModelContext(container)
        let controller = RideSessionController()
        controller.configure(modelContext: restoredContext)
        let restored = try #require(controller.activeRide)
        defer { controller.endRide() }
        #expect(controller.isTrackingLocation)
        #expect(restored.lastResumedAt == start.addingTimeInterval(20))
        controller.recordLocation(sample(at: start.addingTimeInterval(-5)))
        controller.recordLocation(sample(at: start.addingTimeInterval(15)))
        controller.recordLocation(sample(at: .now.addingTimeInterval(60)))
        controller.recordLocation(sample(at: start.addingTimeInterval(25), accuracy: -1))
        controller.recordLocation(sample(at: start.addingTimeInterval(25), accuracy: 101))
        controller.recordLocation(sample(at: start.addingTimeInterval(25), latitude: 91))
        #expect(restored.routePoints.isEmpty)
        controller.recordLocation(sample(at: start.addingTimeInterval(25)))
        #expect(restored.routePoints.count == 1)
    }

    @Test func restoringPausedRideDoesNotStartLocationServices() throws {
        let container = try makeContainer()
        let ride = TrackedRide()
        ride.pause()
        container.mainContext.insert(ride)
        try container.mainContext.save()
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)
        controller.resumeLocationUpdatesIfNeeded()
        #expect(controller.activeRide === ride)
        #expect(!controller.isTrackingLocation)
    }

    @Test func appDeclaresBackgroundLocationAndExplainsItsUse() throws {
        let modes = try #require(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        #expect(modes.contains("location"))
        let purpose = try #require(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String)
        #expect(purpose.contains("Maps"))
        #expect(purpose.contains("pause or end"))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    private func sample(at timestamp: Date, accuracy: Double = 5, latitude: Double = 37) -> RideLocationSample {
        RideLocationSample(
            latitude: latitude, longitude: -122, horizontalAccuracy: accuracy,
            speed: 5, speedAccuracy: 1, timestamp: timestamp
        )
    }
}
