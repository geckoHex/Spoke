import CoreLocation
import Foundation

/// Scalar route metrics shared by recording, history, and statistics.
struct RideRouteSummary: Equatable {
    var pointCount = 0
    var distanceInMeters: CLLocationDistance = 0
    var movingDuration: TimeInterval = 0
    var movingDistanceInMeters: CLLocationDistance = 0
    var topSpeedInMilesPerHour: Double?

    init() {}

    init(points: [RideRoutePoint]) {
        let points = points.sorted { $0.recordedAt < $1.recordedAt }
        var previous: RideRoutePoint?
        for point in points {
            append(point, after: previous)
            previous = point
        }
    }

    mutating func append(_ point: RideRoutePoint, after previous: RideRoutePoint?) {
        pointCount += 1
        guard let previous else { return }

        let start = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
        let end = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let distance = end.distance(from: start)
        distanceInMeters += distance

        // Distance includes every adjacent pair; speed requires distinct timestamps.
        let duration = point.recordedAt.timeIntervalSince(previous.recordedAt)
        guard duration > 0 else { return }
        let speed = distance / duration * 2.236_936_292_1
        topSpeedInMilesPerHour = max(topSpeedInMilesPerHour ?? speed, speed)
        if speed > RideRouteSpeed.littleMotionThreshold {
            movingDuration += duration
            movingDistanceInMeters += distance
        }
    }

    var movingMetrics: RideMovingMetrics {
        RideMovingMetrics(duration: movingDuration, distanceInMeters: movingDistanceInMeters)
    }
}
