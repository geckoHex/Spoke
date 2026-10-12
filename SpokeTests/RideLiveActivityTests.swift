import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct RideLiveActivityTests {
    @Test func snapshotUsesSavedDistanceAndExcludesPausedTime() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let ride = TrackedRide(startedAt: start)
        ride.routePoints = [
            RideRoutePoint(latitude: 0, longitude: 0, horizontalAccuracy: 5, recordedAt: start),
            RideRoutePoint(latitude: 0, longitude: 0.01, horizontalAccuracy: 5, recordedAt: start.addingTimeInterval(60)),
        ]
        ride.pause(at: start.addingTimeInterval(65))
        let paused = snapshot(ride, at: start.addingTimeInterval(90))
        #expect(paused.state.elapsedDuration == 65)
        #expect(paused.state.speedInMilesPerHour == 0)
        #expect(paused.state.isPaused)
        #expect(paused.state.distanceInMiles == RideMetrics.distanceInMeters(for: ride) / 1_609.344)

        ride.resume(at: start.addingTimeInterval(95))
        let resumed = snapshot(ride, at: start.addingTimeInterval(105))
        #expect(resumed.state.elapsedDuration == 75)
        #expect(resumed.state.timerStartDate == start.addingTimeInterval(30))
        #expect(resumed.state.speedInMilesPerHour == 16)
        #expect(!resumed.state.isPaused)
        #expect(resumed.rideID == paused.rideID)

        let encoded = try JSONEncoder().encode(resumed.state)
        #expect(try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: encoded) == resumed.state)
    }

    @Test func unavailableLocationDoesNotAdvertiseAnOldSpeed() {
        let ride = TrackedRide()
        let snapshot = RideLiveActivitySnapshot(
            ride: ride, speedInMilesPerHour: 16, locationStatus: .unavailable, at: .now
        )
        #expect(snapshot.state.speedInMilesPerHour == nil)
    }

    @Test func liveActivityFollowsOnlySuccessfulRideActions() throws {
        let container = try makeContainer()
        container.mainContext.autosaveEnabled = false
        let activity = RecordingLiveActivity()
        var shouldFail = true
        let controller = RideSessionController(liveActivity: activity) { context in
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        controller.configure(modelContext: container.mainContext)
        let initialCount = activity.snapshots.count

        #expect(controller.startRide() == nil)
        #expect(activity.snapshots.count == initialCount)
        shouldFail = false
        let ride = try #require(controller.startRide())
        ride.startAddress = "Test start"
        #expect(activity.latest?.rideID == ride.liveActivityID.uuidString)
        #expect(activity.requestIfNeeded)
        let runningCount = activity.snapshots.count

        shouldFail = true
        controller.togglePause()
        #expect(activity.snapshots.count == runningCount)
        #expect(activity.latest?.state.isPaused == false)
        shouldFail = false
        controller.togglePause()
        #expect(activity.latest?.state.isPaused == true)
        #expect(!controller.isTrackingLocation)
        let pausedCount = activity.snapshots.count

        shouldFail = true
        controller.togglePause()
        #expect(activity.snapshots.count == pausedCount)
        #expect(controller.endRide() == nil)
        #expect(activity.latest?.state.isPaused == true)
        shouldFail = false
        controller.togglePause()
        #expect(activity.latest?.state.isPaused == false)
        #expect(controller.isTrackingLocation)
        #expect(controller.endRide() === ride)
        #expect(activity.latest == nil)
    }

    @Test func repeatedAndOldButtonsCannotToggleAnotherRide() async throws {
        let container = try makeContainer()
        let activity = RecordingLiveActivity()
        let controller = RideSessionController(liveActivity: activity)
        controller.configure(modelContext: container.mainContext)
        let start = Date.now.addingTimeInterval(-120)
        let ride = try #require(controller.startRide(at: start))
        ride.startAddress = "Test start"
        let rideID = ride.liveActivityID.uuidString

        try await controller.setPausedFromLiveActivity(rideID: rideID, isPaused: true, at: start.addingTimeInterval(10))
        try await controller.setPausedFromLiveActivity(rideID: rideID, isPaused: true, at: start.addingTimeInterval(20))
        #expect(ride.pausedAt == start.addingTimeInterval(10))
        #expect(!controller.isTrackingLocation)
        #expect(activity.flushCount == 2)

        try await controller.setPausedFromLiveActivity(rideID: rideID, isPaused: false, at: start.addingTimeInterval(30))
        try await controller.setPausedFromLiveActivity(rideID: rideID, isPaused: false, at: start.addingTimeInterval(40))
        #expect(ride.accumulatedPausedDuration == 20)
        #expect(ride.lastResumedAt == start.addingTimeInterval(30))
        #expect(controller.isTrackingLocation)
        controller.endRide()

        let nextRide = try #require(controller.startRide())
        nextRide.startAddress = "Test start"
        defer { controller.endRide() }
        await #expect(throws: RideLiveActivityActionError.self) {
            try await controller.setPausedFromLiveActivity(rideID: rideID, isPaused: true)
        }
        #expect(!nextRide.isPaused)
        #expect(activity.latest?.rideID == nextRide.liveActivityID.uuidString)
    }

    @Test func failedIntentLeavesTheActivityAndTrackingUnchanged() async throws {
        let container = try makeContainer()
        container.mainContext.autosaveEnabled = false
        let activity = RecordingLiveActivity()
        var shouldFail = false
        let controller = RideSessionController(liveActivity: activity) { context in
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        controller.configure(modelContext: container.mainContext)
        let ride = try #require(controller.startRide())
        ride.startAddress = "Test start"
        shouldFail = true
        await #expect(throws: RideLiveActivityActionError.self) {
            try await controller.setPausedFromLiveActivity(rideID: ride.liveActivityID.uuidString, isPaused: true)
        }
        #expect(!ride.isPaused)
        #expect(controller.isTrackingLocation)
        #expect(activity.latest?.state.isPaused == false)
        shouldFail = false
        controller.endRide()
    }

    @Test func restoringPausedRideKeepsItsIdentityAndFrozenTimer() throws {
        let container = try makeContainer()
        let ride = TrackedRide(startedAt: .now.addingTimeInterval(-120))
        ride.startAddress = "Test start"
        ride.pause(at: ride.startedAt.addingTimeInterval(45))
        container.mainContext.insert(ride)
        try container.mainContext.save()
        let activity = RecordingLiveActivity()
        let controller = RideSessionController(liveActivity: activity)
        controller.configure(modelContext: ModelContext(container))
        defer { controller.endRide() }

        #expect(activity.latest?.rideID == ride.liveActivityID.uuidString)
        #expect(activity.latest?.state.elapsedDuration == 45)
        #expect(activity.latest?.state.isPaused == true)
        #expect(!controller.isTrackingLocation)
    }

    @Test func appEnablesLiveActivitiesAndEmbedsItsExtension() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true)
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let extensionBundle = try #require(Bundle(url: plugins.appendingPathComponent("SpokeLiveActivity.appex")))
        let configuration = try #require(extensionBundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        #expect(configuration["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
    }

    private func snapshot(_ ride: TrackedRide, at date: Date) -> RideLiveActivitySnapshot {
        RideLiveActivitySnapshot(ride: ride, speedInMilesPerHour: 16, locationStatus: .recording, at: date)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }
}

@MainActor
private final class RecordingLiveActivity: RideLiveActivityManaging {
    var snapshots: [RideLiveActivitySnapshot?] = []
    var requestIfNeeded = false
    var flushCount = 0

    var latest: RideLiveActivitySnapshot? { snapshots.last ?? nil }

    func synchronize(_ snapshot: RideLiveActivitySnapshot?, requestIfNeeded: Bool) {
        snapshots.append(snapshot)
        self.requestIfNeeded = requestIfNeeded
    }

    func flush() async {
        flushCount += 1
    }
}
