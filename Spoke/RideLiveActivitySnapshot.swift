import Foundation

struct RideLiveActivitySnapshot: Equatable {
    let rideID: String
    let state: RideActivityAttributes.ContentState

    init(
        ride: TrackedRide,
        distanceInMeters: Double,
        speedInMilesPerHour: Int,
        locationStatus: RideLocationStatus,
        at date: Date
    ) {
        rideID = ride.liveActivityID.uuidString
        state = RideActivityAttributes.ContentState(
            timerStartDate: ride.startedAt.addingTimeInterval(ride.accumulatedPausedDuration),
            elapsedDuration: ride.elapsedDuration(at: date),
            distanceInMiles: distanceInMeters / 1_609.344,
            speedInMilesPerHour: ride.isPaused || ride.isWalking ? 0
                : (locationStatus == .recording ? max(speedInMilesPerHour, 0) : nil),
            isPaused: ride.isPaused,
            isWalking: ride.isWalking
        )
    }
}

@MainActor
protocol RideLiveActivityManaging {
    func synchronize(_ snapshot: RideLiveActivitySnapshot?, requestIfNeeded: Bool)
    func flush() async
}
