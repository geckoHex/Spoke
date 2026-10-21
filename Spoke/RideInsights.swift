import CoreLocation
import Foundation

enum RideSpeedBand: Int, CaseIterable, Identifiable {
    case underFive, fiveToTen, tenToFifteen, fifteenPlus

    var id: Int { rawValue }
    var label: String { ["0–5 mph", "5–10 mph", "10–15 mph", "15+ mph"][rawValue] }

    static func band(for speed: Double) -> Self {
        if speed < 5 { return .underFive }
        if speed < 10 { return .fiveToTen }
        if speed < 15 { return .tenToFifteen }
        return .fifteenPlus
    }
}

struct RideTimeBreakdown {
    private(set) var secondsByBand = Array(repeating: 0.0, count: RideSpeedBand.allCases.count)
    private(set) var moving: TimeInterval = 0
    private(set) var stopped: TimeInterval = 0

    var recorded: TimeInterval { moving + stopped }

    init(rides: [TrackedRide]) {
        for ride in rides {
            for segment in RideRecordedSegment.segments(for: ride) {
                // Older paused rides do not identify where their pauses occurred.
                guard ride.accumulatedPausedDuration == 0 || segment.hasRecordingBoundary else { continue }
                secondsByBand[RideSpeedBand.band(for: segment.speed).rawValue] += segment.duration
                if segment.speed > RideRouteSpeed.littleMotionThreshold {
                    moving += segment.duration
                } else {
                    stopped += segment.duration
                }
            }
        }
    }
}

struct RideRecordedSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let duration: TimeInterval
    let distance: Double
    let hasRecordingBoundary: Bool

    var speed: Double { distance / duration * 2.236_936_292_1 }

    static func segments(for ride: TrackedRide) -> [Self] {
        guard let endedAt = ride.endedAt else { return [] }
        let points = ride.routePoints.sorted { $0.recordedAt < $1.recordedAt }
        return zip(points, points.dropFirst()).compactMap { first, last in
            let duration = last.recordedAt.timeIntervalSince(first.recordedAt)
            // shortcut: Infer motion from fixes at most 30 seconds apart; use saved speed samples if finer precision is needed.
            guard duration > 0, duration <= 30,
                  first.formsCyclingSegment(with: last),
                  first.recordedAt >= ride.startedAt, last.recordedAt <= endedAt,
                  first.recordingStartedAt == last.recordingStartedAt,
                  (0...50).contains(first.horizontalAccuracy),
                  (0...50).contains(last.horizontalAccuracy)
            else { return nil }
            let start = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            let end = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
            guard CLLocationCoordinate2DIsValid(start), CLLocationCoordinate2DIsValid(end) else { return nil }
            let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            return Self(start: start, end: end, duration: duration, distance: distance,
                        hasRecordingBoundary: first.recordingStartedAt != nil)
        }
    }
}
