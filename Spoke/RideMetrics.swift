//
//  RideMetrics.swift
//  Spoke
//

import CoreLocation
import Foundation

enum RideMetrics {
    static func duration(
        _ interval: TimeInterval,
        omittingZeroHours: Bool = false
    ) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if omittingZeroHours, hours == 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        }

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func distanceInMeters(for ride: TrackedRide) -> CLLocationDistance {
        let points = ride.routePoints.sorted { $0.recordedAt < $1.recordedAt }
        guard points.count > 1 else { return 0 }

        return zip(points, points.dropFirst()).reduce(0) { distance, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return distance + end.distance(from: start)
        }
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        "\(miles(meters)) mi"
    }

    static func miles(_ meters: CLLocationDistance) -> String {
        String(format: "%.1f", meters / 1_609.344)
    }

    static func ageDescription(since date: Date, relativeTo currentDate: Date) -> String {
        let totalSeconds = max(Int(currentDate.timeIntervalSince(date)), 0)
        let denominations: [(seconds: Int, name: String)] = [
            (31_536_000, "year"),
            (2_592_000, "month"),
            (604_800, "week"),
            (86_400, "day"),
            (3_600, "hour"),
            (60, "minute"),
            (1, "second"),
        ]

        let denomination = denominations.first { totalSeconds >= $0.seconds }
            ?? denominations[denominations.count - 1]
        let value = totalSeconds / denomination.seconds
        let unit = value == 1 ? denomination.name : "\(denomination.name)s"
        return "\(value) \(unit) ago"
    }
}
