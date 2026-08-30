//
//  RideRouteSpeed.swift
//  Spoke
//

import CoreLocation
import Foundation

enum RideRouteMotion: Equatable {
    case normalOrFaster
    case slower
    case stopped
}

struct RideRouteSegment {
    var coordinates: [CLLocationCoordinate2D]
    let motion: RideRouteMotion
}

enum RideRouteSpeed {
    static let littleMotionThreshold = 1.0

    static func segments(for points: [RideRoutePoint]) -> [RideRouteSegment] {
        let sortedPoints = points.sorted { $0.recordedAt < $1.recordedAt }
        let measuredSegments = zip(sortedPoints, sortedPoints.dropFirst()).compactMap {
            startPoint,
            endPoint -> MeasuredSegment? in
            let duration = endPoint.recordedAt.timeIntervalSince(startPoint.recordedAt)
            guard duration > 0 else { return nil }

            let startLocation = CLLocation(
                latitude: startPoint.latitude,
                longitude: startPoint.longitude
            )
            let endLocation = CLLocation(
                latitude: endPoint.latitude,
                longitude: endPoint.longitude
            )
            let speedInMilesPerHour = endLocation.distance(from: startLocation)
                / duration
                * 2.236_936_292_1

            return MeasuredSegment(
                start: startLocation.coordinate,
                end: endLocation.coordinate,
                speedInMilesPerHour: speedInMilesPerHour
            )
        }

        let normalSpeed = typicalMovingSpeed(
            measuredSegments.map(\.speedInMilesPerHour)
        )

        return measuredSegments.reduce(into: []) { segments, measuredSegment in
            let motion = motion(
                for: measuredSegment.speedInMilesPerHour,
                normalSpeed: normalSpeed
            )

            if segments.last?.motion == motion {
                segments[segments.count - 1].coordinates.append(measuredSegment.end)
            } else {
                segments.append(
                    RideRouteSegment(
                        coordinates: [measuredSegment.start, measuredSegment.end],
                        motion: motion
                    )
                )
            }
        }
    }

    static func typicalMovingSpeed(_ speeds: [Double]) -> Double? {
        let movingSpeeds = speeds
            .filter { $0 > littleMotionThreshold }
            .sorted()
        guard !movingSpeeds.isEmpty else { return nil }

        let middleIndex = movingSpeeds.count / 2
        if movingSpeeds.count.isMultiple(of: 2) {
            return (movingSpeeds[middleIndex - 1] + movingSpeeds[middleIndex]) / 2
        }

        return movingSpeeds[middleIndex]
    }

    static func motion(
        for speedInMilesPerHour: Double,
        normalSpeed: Double?
    ) -> RideRouteMotion {
        guard speedInMilesPerHour > littleMotionThreshold else { return .stopped }
        guard let normalSpeed, speedInMilesPerHour < normalSpeed else {
            return .normalOrFaster
        }

        return .slower
    }
}

private struct MeasuredSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let speedInMilesPerHour: Double
}
