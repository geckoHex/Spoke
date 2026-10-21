import ActivityKit
import Foundation

nonisolated struct RideActivityAttributes: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var timerStartDate: Date
        var elapsedDuration: TimeInterval
        var distanceInMiles: Double
        var speedInMilesPerHour: Int?
        var isPaused: Bool
        var isWalking: Bool? = nil

        var statusTitle: String { isPaused ? "Paused" : (isWalking == true ? "Walking" : "Riding") }
        var statusSymbol: String { isPaused ? "pause.fill" : (isWalking == true ? "figure.walk" : "bicycle") }
    }

    let rideID: String
}
