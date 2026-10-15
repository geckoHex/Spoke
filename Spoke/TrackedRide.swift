//
//  TrackedRide.swift
//  Spoke
//

import Foundation
import SwiftData

@Model
final class TrackedRide {
    var liveActivityID: UUID = UUID()
    var startedAt: Date
    var customName: String?
    var note: String?
    var startAddress: String?
    var endAddress: String?
    var endedAt: Date?
    var pausedAt: Date?
    var lastResumedAt: Date?
    var accumulatedPausedDuration: TimeInterval

    // Optional for existing stores. Raw points remain the source for maps and replay.
    var totalDistanceInMeters: Double?
    var movingDuration: TimeInterval?
    var movingDistanceInMeters: Double?
    var topSpeedInMilesPerHour: Double?
    var routeSummaryPointCount: Int?

    @Relationship(deleteRule: .cascade, inverse: \RideRoutePoint.ride)
    var routePoints: [RideRoutePoint]

    @Relationship(deleteRule: .cascade, inverse: \RideSoundtrackEntry.ride)
    var soundtrackEntries: [RideSoundtrackEntry]

    init(startedAt: Date = .now) {
        self.startedAt = startedAt
        customName = nil
        note = nil
        startAddress = nil
        endAddress = nil
        endedAt = nil
        pausedAt = nil
        lastResumedAt = nil
        accumulatedPausedDuration = 0
        routePoints = []
        soundtrackEntries = []
    }

    var isPaused: Bool {
        pausedAt != nil && endedAt == nil
    }

    /// Recording updates this alongside routePoints in the same save. Route imports
    /// or edits must rebuild it with RideRouteSummary(points:) before saving.
    var routeSummary: RideRouteSummary {
        get {
            guard let totalDistanceInMeters, let movingDuration,
                  let movingDistanceInMeters, let routeSummaryPointCount
            else { return RideRouteSummary(points: routePoints) }

            var summary = RideRouteSummary()
            summary.pointCount = routeSummaryPointCount
            summary.distanceInMeters = totalDistanceInMeters
            summary.movingDuration = movingDuration
            summary.movingDistanceInMeters = movingDistanceInMeters
            summary.topSpeedInMilesPerHour = topSpeedInMilesPerHour
            return summary
        }
        set {
            totalDistanceInMeters = newValue.distanceInMeters
            movingDuration = newValue.movingDuration
            movingDistanceInMeters = newValue.movingDistanceInMeters
            topSpeedInMilesPerHour = newValue.topSpeedInMilesPerHour
            routeSummaryPointCount = newValue.pointCount
        }
    }

    var automaticName: String? {
        guard let startAddress = RideAddressFormatter.street(from: startAddress),
              let endAddress = RideAddressFormatter.street(from: endAddress)
        else { return nil }

        return "\(startAddress) → \(endAddress)"
    }

    func rename(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customName = trimmedName.isEmpty ? nil : trimmedName
    }

    func updateNote(to note: String) {
        self.note = note.isEmpty ? nil : note
    }

    func elapsedDuration(at date: Date = .now) -> TimeInterval {
        let effectiveEnd = endedAt ?? pausedAt ?? date

        return max(
            effectiveEnd.timeIntervalSince(startedAt)
                - accumulatedPausedDuration,
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
        lastResumedAt = date
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
