//
//  RideMetrics.swift
//  Spoke
//

import CoreLocation
import Foundation

enum RideMetrics {
    static func duration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

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
        String(format: "%.1f mi", meters / 1_609.344)
    }
}
