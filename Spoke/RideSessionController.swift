//
//  RideSessionController.swift
//  Spoke
//

import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RideSessionController {
    private(set) var activeRide: TrackedRide?
    private(set) var speedInMilesPerHour = 0
    private(set) var currentLocation: RideLocationSample?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var locationSessionGeneration = 0
    @ObservationIgnored private var lastRecordedPositionAt: Date?
    @ObservationIgnored private var lastSpotifyTrackIdentity: String?
    @ObservationIgnored private var startAddressTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var endAddressTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private let speedProcessor = RideSpeedProcessor()

    private let positionRecordingInterval: TimeInterval = 5

    func configure(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext

        var descriptor = FetchDescriptor<TrackedRide>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\TrackedRide.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let ride = try? modelContext.fetch(descriptor).first else { return }

        activeRide = ride
        let latestPoint = ride.routePoints.max { $0.recordedAt < $1.recordedAt }
        lastRecordedPositionAt = latestPoint?.recordedAt
        lastSpotifyTrackIdentity = ride.soundtrackEntries
            .max { $0.startedAt < $1.startedAt }?
            .trackIdentity
        currentLocation = latestPoint.map(RideLocationSample.init)

        if let firstPoint = ride.routePoints.min(by: { $0.recordedAt < $1.recordedAt }) {
            resolveStartAddressIfNeeded(RideLocationSample(point: firstPoint), for: ride)
        }

        if !ride.isPaused {
            beginLocationUpdates()
        }
    }

    @discardableResult
    func startRide(at date: Date = .now) -> TrackedRide? {
        guard let modelContext, activeRide == nil else { return nil }

        let ride = TrackedRide(startedAt: date)
        modelContext.insert(ride)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(ride)
            return nil
        }

        activeRide = ride
        currentLocation = nil
        speedInMilesPerHour = 0
        lastRecordedPositionAt = nil
        lastSpotifyTrackIdentity = nil
        beginLocationUpdates()
        return ride
    }

    func togglePause(at date: Date = .now) {
        guard let ride = activeRide, ride.endedAt == nil else { return }

        let previousPausedAt = ride.pausedAt
        let previousPausedDuration = ride.accumulatedPausedDuration

        if ride.isPaused {
            ride.resume(at: date)
        } else {
            ride.pause(at: date)
        }

        do {
            try modelContext?.save()
        } catch {
            ride.pausedAt = previousPausedAt
            ride.accumulatedPausedDuration = previousPausedDuration
            return
        }

        if ride.isPaused {
            endLocationUpdates()
        } else {
            beginLocationUpdates()
        }
    }

    @discardableResult
    func endRide(at date: Date = .now) -> TrackedRide? {
        guard let ride = activeRide, ride.endedAt == nil else { return nil }

        let endingLocation = currentLocation ?? ride.routePoints
            .max(by: { $0.recordedAt < $1.recordedAt })
            .map(RideLocationSample.init)
        let wasPaused = ride.isPaused
        let previousPausedAt = ride.pausedAt
        let previousPausedDuration = ride.accumulatedPausedDuration
        endLocationUpdates()
        ride.end(at: date)

        do {
            try modelContext?.save()
        } catch {
            ride.endedAt = nil
            ride.pausedAt = previousPausedAt
            ride.accumulatedPausedDuration = previousPausedDuration

            if !wasPaused {
                beginLocationUpdates()
            }
            return nil
        }

        activeRide = nil
        currentLocation = nil
        lastRecordedPositionAt = nil
        lastSpotifyTrackIdentity = nil

        if let endingLocation {
            resolveEndAddressIfNeeded(endingLocation, for: ride)
        }

        return ride
    }

    func recordSpotifyCheck(_ track: SpotifyTrack?) {
        let observedIdentity = track?.identity
        defer { lastSpotifyTrackIdentity = observedIdentity }

        guard let track,
              track.isPlaying,
              track.identity != lastSpotifyTrackIdentity,
              let modelContext,
              let ride = activeRide,
              ride.endedAt == nil
        else { return }

        let entry = RideSoundtrackEntry(
            spotifyTrackID: track.spotifyID,
            albumArtURL: track.albumArtURL,
            title: track.title,
            artist: track.artist,
            startedAt: track.playbackStartedAt
        )
        modelContext.insert(entry)
        ride.soundtrackEntries.append(entry)

        do {
            try modelContext.save()
        } catch {
            ride.soundtrackEntries.removeAll { $0 === entry }
            modelContext.delete(entry)
            return
        }

        guard let albumArtURL = track.albumArtURL else { return }
        cacheAlbumArt(from: albumArtURL, for: entry)
    }

    private func cacheAlbumArt(from url: URL, for entry: RideSoundtrackEntry) {
        Task { [weak self, weak entry] in
            guard let self, let entry else { return }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200,
                      data.count <= 5_000_000
                else { return }

                entry.albumArtData = data
                try self.modelContext?.save()
            } catch {
                // The persisted Spotify image URL remains available as a fallback.
            }
        }
    }

    private func beginLocationUpdates() {
        guard locationTask == nil,
              let activeRide,
              !activeRide.isPaused,
              activeRide.endedAt == nil
        else { return }

        locationSessionGeneration += 1
        let generation = locationSessionGeneration
        let processor = speedProcessor
        let publish: @MainActor @Sendable (RideSpeedUpdate) -> Void = { [weak self] update in
            guard let self,
                  self.locationTask != nil,
                  self.locationSessionGeneration == generation
            else { return }

            self.receive(update)
        }

        locationTask = Task.detached(priority: .userInitiated) {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    try Task.checkCancellation()

                    if update.stationary {
                        let processedUpdate = await processor.processStationary()
                        await publish(processedUpdate)
                        continue
                    }

                    guard let location = update.location else { continue }

                    let processedUpdate = await processor.process(
                        [RideLocationSample(location: location)],
                        now: .now
                    )
                    await publish(processedUpdate)
                }
            } catch {
                // Cancellation and unavailable location updates both end quietly.
            }
        }
    }

    private func endLocationUpdates() {
        locationSessionGeneration += 1
        locationTask?.cancel()
        locationTask = nil
        speedInMilesPerHour = 0

        Task {
            await speedProcessor.reset()
        }
    }

    private func receive(_ update: RideSpeedUpdate) {
        guard let ride = activeRide, !ride.isPaused, ride.endedAt == nil else { return }

        if let location = update.mapLocation {
            currentLocation = location
            recordPositionIfNeeded(location, for: ride)
            let startingLocation = ride.routePoints
                .min(by: { $0.recordedAt < $1.recordedAt })
                .map(RideLocationSample.init) ?? location
            resolveStartAddressIfNeeded(startingLocation, for: ride)
        }

        if let speedInMilesPerHour = update.speedInMilesPerHour {
            self.speedInMilesPerHour = speedInMilesPerHour
        }
    }

    private func recordPositionIfNeeded(
        _ location: RideLocationSample,
        for ride: TrackedRide
    ) {
        if let lastRecordedPositionAt,
           location.timestamp.timeIntervalSince(lastRecordedPositionAt)
            < positionRecordingInterval
        {
            return
        }

        guard let modelContext else { return }

        let point = RideRoutePoint(
            latitude: location.latitude,
            longitude: location.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            recordedAt: location.timestamp
        )
        modelContext.insert(point)
        ride.routePoints.append(point)

        do {
            try modelContext.save()
            lastRecordedPositionAt = location.timestamp
        } catch {
            ride.routePoints.removeAll { $0 === point }
            modelContext.delete(point)
        }
    }

    private func resolveStartAddressIfNeeded(
        _ location: RideLocationSample,
        for ride: TrackedRide
    ) {
        let rideID = ObjectIdentifier(ride)
        guard ride.startAddress == nil, startAddressTasks[rideID] == nil else { return }

        startAddressTasks[rideID] = Task { @MainActor [weak self, weak ride] in
            defer { self?.startAddressTasks[rideID] = nil }
            guard let address = await RideAddressResolver.endpointName(for: location),
                  let self,
                  let ride,
                  ride.startAddress == nil
            else { return }

            ride.startAddress = address
            try? self.modelContext?.save()
        }
    }

    private func resolveEndAddressIfNeeded(
        _ location: RideLocationSample,
        for ride: TrackedRide
    ) {
        let rideID = ObjectIdentifier(ride)
        guard ride.endAddress == nil, endAddressTasks[rideID] == nil else { return }

        endAddressTasks[rideID] = Task { @MainActor [weak self, weak ride] in
            defer { self?.endAddressTasks[rideID] = nil }
            guard let address = await RideAddressResolver.endpointName(for: location),
                  let self,
                  let ride,
                  ride.endAddress == nil
            else { return }

            ride.endAddress = address
            try? self.modelContext?.save()
        }
    }
}

struct RideLocationSample: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
    let speedAccuracy: CLLocationSpeedAccuracy
    let timestamp: Date

    nonisolated init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: CLLocationAccuracy,
        speed: CLLocationSpeed,
        speedAccuracy: CLLocationSpeedAccuracy,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.timestamp = timestamp
    }

    nonisolated init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        timestamp = location.timestamp
    }

    nonisolated init(point: RideRoutePoint) {
        latitude = point.latitude
        longitude = point.longitude
        horizontalAccuracy = point.horizontalAccuracy
        speed = 0
        speedAccuracy = 0
        timestamp = point.recordedAt
    }
}

struct RideSpeedUpdate: Sendable {
    let mapLocation: RideLocationSample?
    let speedInMilesPerHour: Int?
}

actor RideSpeedProcessor {
    private let metersPerSecondToMilesPerHour = 2.236_936_292_1
    private let maximumLocationAge: TimeInterval = 2
    private let maximumMapHorizontalAccuracy: CLLocationAccuracy = 100
    private let maximumSpeedAccuracy: CLLocationSpeedAccuracy = 3
    private let maximumCyclingSpeed: CLLocationSpeed = 45
    private let maximumCyclingAcceleration: CLLocationSpeed = 4
    private let smoothingTimeConstant: TimeInterval = 0.35
    private let stationarySpeed: CLLocationSpeed = 0.45

    private var filteredSpeed: CLLocationSpeed?
    private var lastAcceptedSample: RideLocationSample?

    func process(_ samples: [RideLocationSample], now: Date) -> RideSpeedUpdate {
        let mapLocation = samples.last { isValidForMap($0, now: now) }
        var newestFilteredSpeed: CLLocationSpeed?

        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard isValid(sample, now: now), isPlausible(sample) else { continue }

            newestFilteredSpeed = smooth(sample)
            lastAcceptedSample = sample
        }

        let speed = newestFilteredSpeed.map {
            Int(($0 * metersPerSecondToMilesPerHour).rounded())
        }

        return RideSpeedUpdate(
            mapLocation: mapLocation,
            speedInMilesPerHour: speed
        )
    }

    func reset() {
        filteredSpeed = nil
        lastAcceptedSample = nil
    }

    func processStationary() -> RideSpeedUpdate {
        filteredSpeed = 0
        lastAcceptedSample = nil

        return RideSpeedUpdate(
            mapLocation: nil,
            speedInMilesPerHour: 0
        )
    }

    private func isValid(_ sample: RideLocationSample, now: Date) -> Bool {
        let age = now.timeIntervalSince(sample.timestamp)

        return (-1...maximumLocationAge).contains(age)
            && sample.speed >= 0
            && sample.speed <= maximumCyclingSpeed
            && sample.speedAccuracy >= 0
            && sample.speedAccuracy <= maximumSpeedAccuracy
    }

    private func isValidForMap(_ sample: RideLocationSample, now: Date) -> Bool {
        let age = now.timeIntervalSince(sample.timestamp)

        return (-1...maximumLocationAge).contains(age)
            && sample.horizontalAccuracy >= 0
            && sample.horizontalAccuracy <= maximumMapHorizontalAccuracy
    }

    private func isPlausible(_ sample: RideLocationSample) -> Bool {
        guard let previous = lastAcceptedSample else { return true }

        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }

        let expectedChange = maximumCyclingAcceleration * elapsed
        let uncertainty = sample.speedAccuracy + previous.speedAccuracy

        return abs(sample.speed - previous.speed) <= expectedChange + uncertainty
    }

    private func smooth(_ sample: RideLocationSample) -> CLLocationSpeed {
        let measuredSpeed = sample.speed < stationarySpeed ? 0 : sample.speed

        guard let filteredSpeed,
              let previous = lastAcceptedSample
        else {
            self.filteredSpeed = measuredSpeed
            return measuredSpeed
        }

        let elapsed = max(sample.timestamp.timeIntervalSince(previous.timestamp), 0.05)
        let timeWeight = 1 - exp(-elapsed / smoothingTimeConstant)
        let accuracyRatio = min(sample.speedAccuracy / maximumSpeedAccuracy, 1)
        let accuracyWeight = 1 - (accuracyRatio * 0.25)
        var weight = min(max(timeWeight * accuracyWeight, 0.35), 1)

        if abs(measuredSpeed - filteredSpeed) >= 2 {
            weight = max(weight, 0.8)
        }

        let smoothedSpeed = filteredSpeed + ((measuredSpeed - filteredSpeed) * weight)
        self.filteredSpeed = smoothedSpeed
        return smoothedSpeed
    }
}
