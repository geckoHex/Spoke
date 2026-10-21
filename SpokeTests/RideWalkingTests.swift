import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct RideWalkingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func walkingKeepsTimeAndRouteButExcludesCyclingMetrics() throws {
        let container = try makeContainer()
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        controller.recordLocation(sample(0))
        controller.recordLocation(sample(10))
        let cyclingDistance = controller.distanceInMeters
        #expect(cyclingDistance > 0)

        controller.toggleWalking(at: date(12))
        #expect(ride.isWalking)
        #expect(!ride.isPaused)
        #expect(controller.isTrackingLocation)
        controller.recordLocation(sample(15))
        controller.recordLocation(sample(25, longitude: 0.01))
        #expect(ride.routePoints.count == 4)
        #expect(ride.routePoints.filter(\.isWalking).count == 2)
        #expect(controller.distanceInMeters == cyclingDistance)
        #expect(ride.elapsedDuration(at: date(30)) == 30)
        #expect(ride.cyclingDuration(at: date(30)) == 12)

        let walking = RideLiveActivitySnapshot(ride: ride, distanceInMeters: cyclingDistance,
            speedInMilesPerHour: 18, locationStatus: .recording, at: date(30)).state
        #expect(walking.statusTitle == "Walking")
        #expect(walking.isWalking == true)
        #expect(!walking.isPaused)
        #expect(walking.elapsedDuration == 30)
        #expect(walking.timerStartDate == start)
        #expect(walking.speedInMilesPerHour == 0)

        controller.togglePause(at: date(30))
        #expect(!controller.isTrackingLocation)
        #expect(ride.elapsedDuration(at: date(40)) == 30)
        #expect(ride.cyclingDuration(at: date(40)) == 12)
        controller.toggleWalking(at: date(35))
        #expect(ride.isWalking)
        controller.togglePause(at: date(40))
        #expect(ride.isWalking)
        #expect(controller.isTrackingLocation)
        controller.toggleWalking(at: date(42))
        #expect(!ride.isWalking)
        // Delayed walking fixes must not be relabeled as cycling after resuming.
        controller.recordLocation(sample(41))
        #expect(ride.routePoints.count == 4)
        controller.recordLocation(sample(45))
        #expect(controller.distanceInMeters == cyclingDistance)
        controller.recordLocation(sample(55))
        #expect(controller.distanceInMeters > cyclingDistance)
        #expect(controller.distanceInMeters == RideMetrics.distanceInMeters(for: ride))
        controller.endRide(at: date(60))
        #expect(ride.elapsedDuration() == 50)
        #expect(ride.cyclingDuration() == 30)
        #expect(ride.accumulatedWalkingDuration == 20)
        #expect(!controller.isTrackingLocation)
        #expect(RideRouteSpeed.movingMetrics(for: ride.routePoints).duration == 20)
        #expect(try #require(RideRouteSpeed.topSpeed(for: ride.routePoints)) < 3)
        #expect(RideTimeBreakdown(rides: [ride]).moving == 20)
        #expect(RideRouteSpeed.segments(for: ride.routePoints).contains { $0.motion == .slower })
        let stats = RideStatistics(rides: [ride], period: .allTime, now: date(60))
        #expect(stats.duration == 50)
        #expect(abs(try #require(stats.averageSpeed) - RideMetrics.distanceInMeters(for: ride) / 30 * 2.236_936_292_1) < 0.000_001)
    }

    @Test func walkingRestoresAndFinishesWithItsFullElapsedTime() throws {
        let container = try makeContainer()
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        controller.recordLocation(sample(0))
        controller.recordLocation(sample(10))
        controller.toggleWalking(at: date(12))
        controller.recordLocation(sample(15))

        let restoredController = RideSessionController()
        restoredController.configure(modelContext: ModelContext(container))
        let restored = try #require(restoredController.activeRide)
        defer { controller.endRide(at: date(40)) }
        #expect(restored.isWalking)
        #expect(restored.walkingChangedAt == date(12))
        #expect(restoredController.isTrackingLocation)
        #expect(restoredController.distanceInMeters == controller.distanceInMeters)
        restoredController.recordLocation(sample(25))
        #expect(restored.routePoints.count == 4)
        #expect(restoredController.distanceInMeters == controller.distanceInMeters)
        #expect(restoredController.endRide(at: date(30)) === restored)
        #expect(restored.elapsedDuration() == 30)
        #expect(restored.cyclingDuration() == 12)
        #expect(restored.routePoints.filter(\.isWalking).count == 2)
        #expect(RideRouteSpeed.movingMetrics(for: restored.routePoints).duration == 10)
    }

    @Test func walkWithoutGPSFixesDoesNotBridgeCyclingDistance() throws {
        let container = try makeContainer()
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        defer { controller.endRide(at: date(50)) }
        controller.recordLocation(sample(0))
        controller.recordLocation(sample(10))
        let distance = controller.distanceInMeters
        controller.toggleWalking(at: date(12))
        controller.toggleWalking(at: date(35))
        controller.recordLocation(sample(40))
        #expect(controller.distanceInMeters == distance)
        #expect(RideMetrics.distanceInMeters(for: ride) == distance)
        #expect(RideRouteSpeed.movingMetrics(for: ride.routePoints).duration == 10)
    }

    @Test func failedWalkingChangesAndEndPreserveTrackingAndSavedMode() throws {
        let container = try makeContainer()
        container.mainContext.autosaveEnabled = false
        var shouldFail = false
        let controller = RideSessionController { context in
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        controller.configure(modelContext: container.mainContext)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        shouldFail = true
        controller.toggleWalking(at: date(10))
        #expect(!ride.isWalking)
        #expect(ride.walkingChangedAt == nil)
        #expect(controller.errorMessage != nil)
        #expect(controller.isTrackingLocation)

        shouldFail = false
        controller.toggleWalking(at: date(10))
        #expect(controller.errorMessage == nil)
        shouldFail = true
        controller.toggleWalking(at: date(20))
        #expect(ride.isWalking)
        #expect(ride.walkingChangedAt == date(10))
        #expect(ride.accumulatedWalkingDuration == 0)
        controller.togglePause(at: date(25))
        #expect(!ride.isPaused)
        #expect(ride.accumulatedWalkingDuration == 0)
        #expect(controller.endRide(at: date(30)) == nil)
        #expect(ride.isWalking)
        #expect(ride.endedAt == nil)
        #expect(ride.cyclingDuration(at: date(30)) == 10)
        #expect(controller.isTrackingLocation)
        shouldFail = false
        #expect(controller.endRide(at: date(40)) === ride)
        #expect(ride.cyclingDuration() == 10)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    private func date(_ offset: Double) -> Date { start.addingTimeInterval(offset) }

    private func sample(_ offset: Double, longitude: Double? = nil) -> RideLocationSample {
        RideLocationSample(latitude: 0, longitude: longitude ?? offset / 100_000, horizontalAccuracy: 5,
                           speed: 5, speedAccuracy: 1, timestamp: date(offset))
    }
}
