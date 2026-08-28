//
//  TrackedRide.swift
//  Spoke
//

import Foundation
import SwiftData

@Model
final class TrackedRide {
    var startedAt: Date
    var endedAt: Date?
    var pausedAt: Date?
    var accumulatedPausedDuration: TimeInterval

    @Relationship(deleteRule: .cascade, inverse: \RideRoutePoint.ride)
    var routePoints: [RideRoutePoint]

    init(startedAt: Date = .now) {
        self.startedAt = startedAt
        endedAt = nil
        pausedAt = nil
        accumulatedPausedDuration = 0
        routePoints = []
    }

    var isPaused: Bool {
        pausedAt != nil && endedAt == nil
    }

    func elapsedDuration(at date: Date = .now) -> TimeInterval {
        let effectiveEnd = endedAt ?? date
        let currentPauseDuration = pausedAt.map {
            max(effectiveEnd.timeIntervalSince($0), 0)
        } ?? 0

        return max(
            effectiveEnd.timeIntervalSince(startedAt)
                - accumulatedPausedDuration
                - currentPauseDuration,
            0
        )
    }

    func pause(at date: Date = .now) {
        guard endedAt == nil, pausedAt == nil else { return }
        pausedAt = date
    }

    func resume(at date: Date = .now) {
        guard endedAt == nil, let pausedAt else { return }
        accumulatedPausedDuration += max(date.timeIntervalSince(pausedAt), 0)
        self.pausedAt = nil
    }

    func end(at date: Date = .now) {
        guard endedAt == nil else { return }

        if let pausedAt {
            accumulatedPausedDuration += max(date.timeIntervalSince(pausedAt), 0)
            self.pausedAt = nil
        }

        endedAt = date
    }
}

@Model
final class RideRoutePoint {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var recordedAt: Date
    var ride: TrackedRide?

    init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        recordedAt: Date,
        ride: TrackedRide? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.recordedAt = recordedAt
        self.ride = ride
    }
}
