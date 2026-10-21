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
    var isWalking: Bool = false
    var walkingChangedAt: Date? = nil
    var accumulatedWalkingDuration: TimeInterval = 0

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
        accumulatedWalkingDuration += currentWalkingDuration(at: date)
        pausedAt = date
    }

    func toggleWalking(at date: Date = .now) {
        guard endedAt == nil, !isPaused else { return }
        accumulatedWalkingDuration += currentWalkingDuration(at: date)
        isWalking.toggle()
        walkingChangedAt = date
    }

    func cyclingDuration(at date: Date = .now) -> TimeInterval {
        max(elapsedDuration(at: date) - accumulatedWalkingDuration - currentWalkingDuration(at: date), 0)
    }

    private func currentWalkingDuration(at date: Date) -> TimeInterval {
        guard isWalking, !isPaused, endedAt == nil, let walkingChangedAt else { return 0 }
        return max(date.timeIntervalSince(max(walkingChangedAt, lastResumedAt ?? startedAt)), 0)
    }

    func resume(at date: Date = .now) {
        guard endedAt == nil, let pausedAt else { return }
        accumulatedPausedDuration += max(date.timeIntervalSince(pausedAt), 0)
        lastResumedAt = date
        self.pausedAt = nil
    }

    func end(at date: Date = .now) {
        guard endedAt == nil else { return }
        accumulatedWalkingDuration += currentWalkingDuration(at: date)

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
    var recordingStartedAt: Date? = nil
    var isWalking: Bool = false
    var walkingChangedAt: Date? = nil
    var ride: TrackedRide?

    func formsCyclingSegment(with next: RideRoutePoint) -> Bool {
        // A walk can fall between two fixes without producing a walking point.
        !isWalking && !next.isWalking && walkingChangedAt == next.walkingChangedAt
    }

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
