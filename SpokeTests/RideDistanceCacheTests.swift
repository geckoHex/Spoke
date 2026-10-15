import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct RideDistanceCacheTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func recordingRollbackRetryAndRestorationKeepDistanceConsistent() throws {
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
        defer { controller.endRide() }

        controller.recordLocation(sample(0))
        controller.recordLocation(sample(10))
        let distance = controller.distanceInMeters
        #expect(distance > 0)
        #expect(abs(distance - fullDistance(ride)) < 0.000_001)

        shouldFail = true
        controller.recordLocation(sample(20))
        #expect(ride.routePoints.count == 2)
        #expect(controller.distanceInMeters == distance)
        shouldFail = false
        controller.recordLocation(sample(20))
        controller.recordLocation(sample(10))
        #expect(ride.routePoints.count == 3)
        #expect(abs(controller.distanceInMeters - fullDistance(ride)) < 0.000_001)

        controller.togglePause(at: start.addingTimeInterval(25))
        let restoredController = RideSessionController()
        restoredController.configure(modelContext: ModelContext(container))
        let restored = try #require(restoredController.activeRide)
        #expect(restoredController.distanceInMeters == controller.distanceInMeters)
        restoredController.togglePause(at: start.addingTimeInterval(30))
        restoredController.recordLocation(sample(40))
        #expect(restored.routePoints.count == 4)
        // Preserve the existing distance calculation across pause boundaries.
        #expect(abs(restoredController.distanceInMeters - fullDistance(restored)) < 0.000_001)
        restoredController.endRide(at: start.addingTimeInterval(45))
        #expect(restoredController.distanceInMeters == 0)
    }

    @Test func existingStoreUpgradesWithoutLosingRideOrSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rides.store")
        try writeLegacyStore(at: url)

        let schema = Schema([AppSettings.self, TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let ride = try #require(container.mainContext.fetch(FetchDescriptor<TrackedRide>()).first)
        #expect(ride.customName == "Saved ride")
        #expect(ride.routePoints.count == 2)
        #expect(ride.soundtrackEntries.first?.title == "Saved track")
        let distance = RideMetrics.distanceInMeters(for: ride)
        #expect(distance > 0)
        #expect(distance == fullDistance(ride))
        #expect(try container.mainContext.fetch(FetchDescriptor<AppSettings>()).first?.name == "Rider")
        try container.mainContext.save()
        let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<TrackedRide>()).first)
        #expect(RideMetrics.distanceInMeters(for: reloaded) == distance)
    }

    private func writeLegacyStore(at url: URL) throws {
        let schema = Schema([
            LegacyRideStore.Item.self, LegacyRideStore.AppSettings.self,
            LegacyRideStore.TrackedRide.self, LegacyRideStore.RideRoutePoint.self,
            LegacyRideStore.RideSoundtrackEntry.self,
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = container.mainContext
        let ride = LegacyRideStore.TrackedRide(startedAt: start)
        ride.endedAt = start.addingTimeInterval(10)
        ride.customName = "Saved ride"
        context.insert(ride)
        for offset in [0.0, 10] {
            ride.routePoints.append(LegacyRideStore.RideRoutePoint(
                latitude: 0, longitude: offset / 1_000,
                horizontalAccuracy: 5, recordedAt: start.addingTimeInterval(offset)
            ))
        }
        ride.soundtrackEntries.append(LegacyRideStore.RideSoundtrackEntry(
            spotifyTrackID: "track", albumArtURL: nil, title: "Saved track", artist: "Artist", startedAt: start
        ))
        context.insert(LegacyRideStore.AppSettings(name: "Rider"))
        context.insert(LegacyRideStore.Item(timestamp: start))
        try context.save()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func sample(_ offset: Double) -> RideLocationSample {
        RideLocationSample(latitude: 0, longitude: offset / 1_000, horizontalAccuracy: 5,
                           speed: 5, speedAccuracy: 1, timestamp: start.addingTimeInterval(offset))
    }

    private func fullDistance(_ ride: TrackedRide) -> Double {
        let points = ride.routePoints.sorted { $0.recordedAt < $1.recordedAt }
        return zip(points, points.dropFirst()).reduce(0) { distance, pair in
            distance + CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
                .distance(from: CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude))
        }
    }
}
