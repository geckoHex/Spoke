import ActivityKit
import Foundation

nonisolated struct RideActivityAttributes: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var timerStartDate: Date
        var elapsedDuration: TimeInterval
        var distanceInMiles: Double
        var speedInMilesPerHour: Int?
        var isPaused: Bool
    }

    let rideID: String
}
