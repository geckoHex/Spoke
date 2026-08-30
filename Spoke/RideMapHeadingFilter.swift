//
//  RideMapHeadingFilter.swift
//  Spoke
//

import CoreLocation

struct RideMapHeadingFilter: Sendable {
    private let minimumSpeed: CLLocationSpeed = 2.5
    private let maximumCourseAccuracy: CLLocationDirectionAccuracy = 25
    private let consistencyTolerance: CLLocationDirection = 20
    private let rotationThreshold: CLLocationDirection = 12
    private let initialConfirmationCount = 3
    private let turnConfirmationCount = 2

    private(set) var stableHeading: CLLocationDirection?
    private var candidateHeading: CLLocationDirection?
    private var candidateCount = 0

    nonisolated init() {}

    nonisolated mutating func update(
        with sample: RideLocationSample
    ) -> CLLocationDirection? {
        guard sample.speed >= minimumSpeed,
              sample.course >= 0,
              sample.courseAccuracy >= 0,
              sample.courseAccuracy <= maximumCourseAccuracy
        else {
            clearCandidate()
            return stableHeading
        }

        let measuredHeading = Self.normalized(sample.course)

        if let stableHeading,
           Self.distance(from: stableHeading, to: measuredHeading) < rotationThreshold
        {
            clearCandidate()
            return stableHeading
        }

        if let candidateHeading,
           Self.distance(from: candidateHeading, to: measuredHeading)
            <= consistencyTolerance
        {
            candidateCount += 1
            self.candidateHeading = Self.interpolated(
                from: candidateHeading,
                to: measuredHeading,
                fraction: 1 / Double(candidateCount)
            )
        } else {
            candidateHeading = measuredHeading
            candidateCount = 1
        }

        let requiredCount = stableHeading == nil
            ? initialConfirmationCount
            : turnConfirmationCount
        guard candidateCount >= requiredCount, let candidateHeading else {
            return stableHeading
        }

        stableHeading = candidateHeading
        clearCandidate()
        return stableHeading
    }

    nonisolated mutating func reset() {
        stableHeading = nil
        clearCandidate()
    }

    nonisolated private mutating func clearCandidate() {
        candidateHeading = nil
        candidateCount = 0
    }

    nonisolated private static func normalized(
        _ heading: CLLocationDirection
    ) -> CLLocationDirection {
        let remainder = heading.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    nonisolated private static func signedDifference(
        from start: CLLocationDirection,
        to end: CLLocationDirection
    ) -> CLLocationDirection {
        normalized(end - start + 180) - 180
    }

    nonisolated private static func distance(
        from start: CLLocationDirection,
        to end: CLLocationDirection
    ) -> CLLocationDirection {
        abs(signedDifference(from: start, to: end))
    }

    nonisolated private static func interpolated(
        from start: CLLocationDirection,
        to end: CLLocationDirection,
        fraction: Double
    ) -> CLLocationDirection {
        normalized(start + (signedDifference(from: start, to: end) * fraction))
    }
}
