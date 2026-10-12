import Foundation

struct RideLiveActivitySnapshot: Equatable {
    let rideID: String
    let state: RideActivityAttributes.ContentState

    init(
        ride: TrackedRide,
        speedInMilesPerHour: Int,
        locationStatus: RideLocationStatus,
        at date: Date
    ) {
        rideID = ride.liveActivityID.uuidString
        state = RideActivityAttributes.ContentState(
            timerStartDate: ride.startedAt.addingTimeInterval(ride.accumulatedPausedDuration),
            elapsedDuration: ride.elapsedDuration(at: date),
            distanceInMiles: RideMetrics.distanceInMeters(for: ride) / 1_609.344,
            speedInMilesPerHour: ride.isPaused ? 0
                : (locationStatus == .recording ? max(speedInMilesPerHour, 0) : nil),
            isPaused: ride.isPaused
        )
    }
}

@MainActor
protocol RideLiveActivityManaging {
    func synchronize(_ snapshot: RideLiveActivitySnapshot?, requestIfNeeded: Bool)
    func flush() async
}
