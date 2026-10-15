import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct RideRouteSummaryTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func summaryPreservesDistanceMovingTimeAndSegmentPeak() {
        let points = [
            point(longitude: 0, seconds: 0),
            point(longitude: 0.001, seconds: 10),
            point(longitude: 0.001, seconds: 30),
            point(longitude: 0.002, seconds: 50),
        ]
        let summary = RideRouteSummary(points: Array(points.reversed()))
        let segmentDistance = CLLocation(latitude: 0, longitude: 0.001)
            .distance(from: CLLocation(latitude: 0, longitude: 0))

        #expect(summary.pointCount == 4)
        #expect(abs(summary.distanceInMeters - segmentDistance * 2) < 0.001)
        #expect(summary.movingDuration == 30)
        #expect(abs(summary.movingDistanceInMeters - segmentDistance * 2) < 0.001)
        #expect(abs((summary.topSpeedInMilesPerHour ?? 0) - 24.9015) < 0.001)
        #expect(abs(summary.movingMetrics.averageSpeedInMilesPerHour - 16.6010) < 0.001)
    }

    @Test func missingTimedSegmentsRemainDistinctFromZeroSpeed() {
        let first = point(longitude: 0, seconds: 0)
        let simultaneous = point(longitude: 0.001, seconds: 0)
        for points in [[], [first], [first, simultaneous]] {
            let summary = RideRouteSummary(points: points)
            #expect(summary.topSpeedInMilesPerHour == nil)
            #expect(summary.movingDuration == 0)
            #expect(summary.movingDistanceInMeters == 0)
        }
        #expect(RideRouteSummary(points: [first, simultaneous]).distanceInMeters > 0)

        let stopped = RideRouteSummary(points: [first, point(longitude: 0, seconds: 20)])
        #expect(stopped.topSpeedInMilesPerHour == 0)
        #expect(stopped.distanceInMeters == 0)
    }

    @Test func legacySummariesBackfillInBatchesWithoutChangingRideData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        for index in 0..<101 {
            let ride = TrackedRide(startedAt: start)
            ride.customName = "Ride \(index)"
            ride.note = "Keep this note"
            ride.end(at: start.addingTimeInterval(60))
            context.insert(ride)
            ride.routePoints = [point(longitude: 0, seconds: 0), point(longitude: 0.001, seconds: 10)]
            #expect(ride.routeSummaryPointCount == nil)
            #expect(RideMetrics.distanceInMeters(for: ride) > 0)
        }
        try context.save()

        try RideSessionStore.backfillRouteSummaries(in: container)
        try RideSessionStore.backfillRouteSummaries(in: container)

        let restoredContext = ModelContext(container)
        let rides = try restoredContext.fetch(FetchDescriptor<TrackedRide>())
        #expect(rides.count == 101)
        #expect(try restoredContext.fetchCount(FetchDescriptor<RideRoutePoint>()) == 202)
        for ride in rides {
            #expect(ride.routeSummaryPointCount == 2)
            #expect(ride.routeSummary == RideRouteSummary(points: ride.routePoints))
            #expect(ride.customName?.hasPrefix("Ride ") == true)
            #expect(ride.note == "Keep this note")
            #expect(ride.elapsedDuration() == 60)
        }
    }

    @Test func failedLocationSaveRollsBackSummaryAndRetryCountsTheSegmentOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        var shouldFail = false
        let controller = RideSessionController { context in
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        controller.configure(modelContext: context)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        ride.endAddress = "Test end"
        defer { controller.endRide() }
        let first = RideLocationSample(point: point(longitude: 0, seconds: 0))
        let second = RideLocationSample(point: point(longitude: 0.001, seconds: 10))
        controller.recordLocation(first)
        let previousSummary = ride.routeSummary

        shouldFail = true
        controller.recordLocation(second)
        #expect(ride.routePoints.count == 1)
        #expect(ride.routeSummary == previousSummary)

        shouldFail = false
        controller.recordLocation(second)
        controller.recordLocation(second)
        #expect(ride.routePoints.count == 2)
        #expect(ride.routeSummary == RideRouteSummary(points: ride.routePoints))

        let restoredContext = ModelContext(container)
        let restored = try #require(restoredContext.fetch(FetchDescriptor<TrackedRide>()).first)
        #expect(restored.routeSummaryPointCount == 2)
        #expect(restored.routeSummary == ride.routeSummary)
        #expect(try restoredContext.fetchCount(FetchDescriptor<RideRoutePoint>()) == 2)
    }

    @Test func restoringLegacyRideContinuesItsDistanceAcrossPauseAndResume() throws {
        let container = try makeContainer()
        let ride = TrackedRide(startedAt: start)
        ride.startAddress = "Test start"
        ride.endAddress = "Test end"
        ride.pause(at: start.addingTimeInterval(10))
        container.mainContext.insert(ride)
        ride.routePoints = [point(longitude: 0, seconds: 0)]
        try container.mainContext.save()

        let context = ModelContext(container)
        let controller = RideSessionController()
        controller.configure(modelContext: context)
        let restored = try #require(controller.activeRide)
        defer { controller.endRide() }
        controller.togglePause(at: start.addingTimeInterval(20))
        controller.recordLocation(RideLocationSample(point: point(longitude: 0.001, seconds: 25)))
        #expect(restored.routeSummaryPointCount == 2)
        #expect(restored.routeSummary == RideRouteSummary(points: restored.routePoints))
        #expect(restored.accumulatedPausedDuration == 10)
    }

    private func point(longitude: Double, seconds: TimeInterval) -> RideRoutePoint {
        RideRoutePoint(
            latitude: 0, longitude: longitude, horizontalAccuracy: 5,
            recordedAt: start.addingTimeInterval(seconds)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }
}
