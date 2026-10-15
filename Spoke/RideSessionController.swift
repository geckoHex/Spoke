//
//  RideSessionController.swift
//  Spoke
//

import CoreLocation
import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class RideSessionController {
    var errorMessage: String?
    private(set) var activeRide: TrackedRide?
    private(set) var speedInMilesPerHour = 0
    private(set) var distanceInMeters: CLLocationDistance = 0
    private(set) var currentMapState: RideMapState?
    private(set) var locationStatus: RideLocationStatus = .acquiring

    var currentLocation: RideLocationSample? {
        currentMapState?.location
    }

    var isTrackingLocation: Bool {
        locationTask != nil && serviceSession != nil && backgroundActivity != nil
    }

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var locationSessionGeneration = 0
    @ObservationIgnored private var lastRecordedLocation: RideLocationSample?
    @ObservationIgnored private var lastSpotifyTrackIdentity: String?
    @ObservationIgnored private var startAddressTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var endAddressTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var backgroundActivity: CLBackgroundActivitySession?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private let liveActivity: (any RideLiveActivityManaging)?
    @ObservationIgnored private var lastLiveActivityUpdateAt: Date?

    private let positionRecordingInterval: TimeInterval = 5
    @ObservationIgnored private let saveChanges: (ModelContext) throws -> Void

    init(
        liveActivity: (any RideLiveActivityManaging)? = nil,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.liveActivity = liveActivity
        self.saveChanges = saveChanges
    }

    func configure(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        defer { synchronizeLiveActivity(requestIfNeeded: true) }

        var descriptor = FetchDescriptor<TrackedRide>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\TrackedRide.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let ride = try? modelContext.fetch(descriptor).first else { return }

        activeRide = ride
        distanceInMeters = RideMetrics.distanceInMeters(for: ride)
        let latestPoint = ride.routePoints.max { $0.recordedAt < $1.recordedAt }
        lastRecordedLocation = latestPoint.map(RideLocationSample.init)
        lastSpotifyTrackIdentity = ride.soundtrackEntries
            .max { $0.startedAt < $1.startedAt }?
            .trackIdentity
        currentMapState = latestPoint.map {
            RideMapState(location: RideLocationSample(point: $0), heading: nil)
        }

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
        errorMessage = nil

        let ride = TrackedRide(startedAt: date)
        modelContext.insert(ride)

        do {
            try saveChanges(modelContext)
        } catch {
            errorMessage = "Your ride couldn’t start. Please try again."
            modelContext.delete(ride)
            return nil
        }

        activeRide = ride
        currentMapState = nil
        speedInMilesPerHour = 0
        distanceInMeters = 0
        lastRecordedLocation = nil
        lastSpotifyTrackIdentity = nil
        beginLocationUpdates()
        synchronizeLiveActivity(at: date, requestIfNeeded: true)
        return ride
    }

    func togglePause(at date: Date = .now) {
        guard let ride = activeRide, ride.endedAt == nil else { return }

        errorMessage = nil
        let previousPausedAt = ride.pausedAt
        let previousPausedDuration = ride.accumulatedPausedDuration
        let previousResumedAt = ride.lastResumedAt

        if ride.isPaused {
            ride.resume(at: date)
        } else {
            ride.pause(at: date)
        }

        do {
            if let modelContext { try saveChanges(modelContext) }
        } catch {
            errorMessage = "Your ride couldn’t \(previousPausedAt == nil ? "pause" : "resume"). Please try again."
            ride.pausedAt = previousPausedAt
            ride.accumulatedPausedDuration = previousPausedDuration
            ride.lastResumedAt = previousResumedAt
            return
        }

        if ride.isPaused {
            endLocationUpdates()
        } else {
            beginLocationUpdates()
        }
        synchronizeLiveActivity(at: date)
    }

    func setPausedFromLiveActivity(
        rideID: String,
        isPaused: Bool,
        at date: Date = .now
    ) async throws {
        guard let ride = activeRide,
              ride.liveActivityID.uuidString == rideID,
              ride.endedAt == nil
        else { throw RideLiveActivityActionError.rideUnavailable }

        // A repeated tap on an old Pause button must not resume the ride.
        if ride.isPaused != isPaused {
            togglePause(at: date)
            guard ride.isPaused == isPaused else {
                throw RideLiveActivityActionError.saveFailed
            }
        } else {
            synchronizeLiveActivity(at: date)
        }
        await liveActivity?.flush()
    }

    @discardableResult
    func endRide(at date: Date = .now) -> TrackedRide? {
        guard let ride = activeRide, ride.endedAt == nil else { return nil }

        errorMessage = nil
        let endingLocation = currentLocation ?? ride.routePoints
            .max(by: { $0.recordedAt < $1.recordedAt })
            .map(RideLocationSample.init)
        let wasPaused = ride.isPaused
        let previousPausedAt = ride.pausedAt
        let previousPausedDuration = ride.accumulatedPausedDuration
        endLocationUpdates()
        ride.end(at: date)

        do {
            if let modelContext { try saveChanges(modelContext) }
        } catch {
            errorMessage = "Your ride couldn’t finish saving. It is still open; please try again."
            ride.endedAt = nil
            ride.pausedAt = previousPausedAt
            ride.accumulatedPausedDuration = previousPausedDuration

            if !wasPaused {
                beginLocationUpdates()
            }
            return nil
        }

        activeRide = nil
        distanceInMeters = 0
        currentMapState = nil
        lastRecordedLocation = nil
        lastSpotifyTrackIdentity = nil
        synchronizeLiveActivity(at: date)

        if let endingLocation {
            resolveEndAddressIfNeeded(endingLocation, for: ride)
        }

        return ride
    }

    @discardableResult
    func discardRide(_ ride: TrackedRide) -> Bool {
        guard let modelContext,
              activeRide !== ride,
              ride.endedAt != nil
        else { return false }

        modelContext.delete(ride)

        do {
            try saveChanges(modelContext)
        } catch {
            modelContext.rollback()
            return false
        }

        let rideID = ObjectIdentifier(ride)
        startAddressTasks.removeValue(forKey: rideID)?.cancel()
        endAddressTasks.removeValue(forKey: rideID)?.cancel()
        return true
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

        guard UIApplication.shared.applicationState != .background
                || CLLocationManager().authorizationStatus != .notDetermined
        else { return }

        locationStatus = .acquiring
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundActivity = CLBackgroundActivitySession()
        locationSessionGeneration += 1
        let generation = locationSessionGeneration
        let processor = RideSpeedProcessor()
        let publish: @MainActor @Sendable (RideSpeedUpdate?, RideLocationStatus?, Bool, RideLocationSample?) -> Void = { [weak self] update, status, stationary, location in
            guard let self,
                  self.locationTask != nil,
                  self.locationSessionGeneration == generation
            else { return }

            if let location { self.recordLocation(location) }
            self.locationStatus = status ?? self.locationStatus.receiving(
                hasUsableLocation: update?.mapLocation != nil,
                stationary: stationary
            )
            if let update { self.receive(update) }
            if self.locationStatus != .recording { self.speedInMilesPerHour = 0 }
            self.synchronizeLiveActivity(force: false)
        }
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.locationSessionGeneration == generation else { return }
            self.endLocationUpdates()
            self.synchronizeLiveActivity()
        }

        locationTask = Task.detached(priority: .userInitiated) {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    try Task.checkCancellation()

                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        await publish(nil, .denied, false, nil)
                        continue
                    }
                    if update.authorizationRestricted {
                        await publish(nil, .restricted, false, nil)
                        continue
                    }
                    if update.locationUnavailable {
                        await publish(nil, .unavailable, false, nil)
                        continue
                    }

                    if update.stationary {
                        let position = if let location = update.location {
                            await processor.process([RideLocationSample(location: location)], now: .now)
                        } else {
                            nil as RideSpeedUpdate?
                        }
                        let stopped = await processor.processStationary()
                        await publish(RideSpeedUpdate(
                            mapLocation: position?.mapLocation,
                            mapHeading: position?.mapHeading,
                            speedInMilesPerHour: stopped.speedInMilesPerHour
                        ), nil, true, update.location.map(RideLocationSample.init))
                        continue
                    }

                    guard let location = update.location else { continue }

                    let sample = RideLocationSample(location: location)
                    let processedUpdate = await processor.process(
                        [sample],
                        now: .now
                    )
                    await publish(processedUpdate, nil, false, sample)
                }
                await publish(nil, .unavailable, false, nil)
            } catch is CancellationError {
                return
            } catch {
                await publish(nil, .unavailable, false, nil)
            }
            await finish()
        }
    }

    func resumeLocationUpdatesIfNeeded() {
        beginLocationUpdates()
        synchronizeLiveActivity(requestIfNeeded: true)
    }

    func retryLocation() {
        endLocationUpdates()
        beginLocationUpdates()
        synchronizeLiveActivity()
    }

    private func synchronizeLiveActivity(
        at date: Date = .now,
        force: Bool = true,
        requestIfNeeded: Bool = false
    ) {
        guard let liveActivity else { return }
        // The system renders the ticking timer; GPS snapshots need at most one update per five seconds.
        if !force, let lastLiveActivityUpdateAt,
           date.timeIntervalSince(lastLiveActivityUpdateAt) < 5 {
            return
        }
        lastLiveActivityUpdateAt = date
        let snapshot = activeRide.map {
            RideLiveActivitySnapshot(
                ride: $0,
                distanceInMeters: distanceInMeters,
                speedInMilesPerHour: speedInMilesPerHour,
                locationStatus: locationStatus,
                at: date
            )
        }
        liveActivity.synchronize(snapshot, requestIfNeeded: requestIfNeeded)
    }

    private func endLocationUpdates() {
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        serviceSession?.invalidate()
        serviceSession = nil
        locationSessionGeneration += 1
        locationTask?.cancel()
        locationTask = nil
        speedInMilesPerHour = 0
    }

    private func receive(_ update: RideSpeedUpdate) {
        guard let ride = activeRide, !ride.isPaused, ride.endedAt == nil else { return }

        if let location = update.mapLocation {
            currentMapState = RideMapState(
                location: location,
                heading: update.mapHeading ?? currentMapState?.heading
            )
        }

        if let speedInMilesPerHour = update.speedInMilesPerHour {
            self.speedInMilesPerHour = speedInMilesPerHour
        }
    }

    func recordLocation(
        _ location: RideLocationSample,
        now: Date = .now
    ) {
        // Background delivery can be delayed; only live speed needs a fresh fix.
        guard let ride = activeRide, !ride.isPaused, ride.endedAt == nil,
              location.timestamp >= max(ride.startedAt, ride.lastResumedAt ?? ride.startedAt),
              location.timestamp <= now.addingTimeInterval(1),
              (0...100).contains(location.horizontalAccuracy),
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(
                latitude: location.latitude, longitude: location.longitude
              ))
        else { return }

        if let lastRecordedLocation,
           location.timestamp.timeIntervalSince(lastRecordedLocation.timestamp)
            < positionRecordingInterval
        {
            return
        }

        guard let modelContext else { return }

        let addedDistance = lastRecordedLocation.map { previous in
            CLLocation(latitude: location.latitude, longitude: location.longitude)
                .distance(from: CLLocation(latitude: previous.latitude, longitude: previous.longitude))
        } ?? 0
        let point = RideRoutePoint(
            latitude: location.latitude,
            longitude: location.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            recordedAt: location.timestamp
        )
        point.recordingStartedAt = ride.lastResumedAt ?? ride.startedAt
        modelContext.insert(point)
        ride.routePoints.append(point)

        do {
            try saveChanges(modelContext)
            lastRecordedLocation = location
            distanceInMeters += addedDistance
            let startingLocation = ride.routePoints
                .min(by: { $0.recordedAt < $1.recordedAt })
                .map(RideLocationSample.init) ?? location
            resolveStartAddressIfNeeded(startingLocation, for: ride)
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
    let course: CLLocationDirection
    let courseAccuracy: CLLocationDirectionAccuracy
    let timestamp: Date

    nonisolated init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: CLLocationAccuracy,
        speed: CLLocationSpeed,
        speedAccuracy: CLLocationSpeedAccuracy,
        course: CLLocationDirection = -1,
        courseAccuracy: CLLocationDirectionAccuracy = -1,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.timestamp = timestamp
    }

    nonisolated init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        course = location.course
        courseAccuracy = location.courseAccuracy
        timestamp = location.timestamp
    }

    nonisolated init(point: RideRoutePoint) {
        latitude = point.latitude
        longitude = point.longitude
        horizontalAccuracy = point.horizontalAccuracy
        speed = 0
        speedAccuracy = 0
        course = -1
        courseAccuracy = -1
        timestamp = point.recordedAt
    }
}

struct RideMapState: Hashable, Sendable {
    let location: RideLocationSample
    let heading: CLLocationDirection?
}

struct RideSpeedUpdate: Sendable {
    let mapLocation: RideLocationSample?
    let mapHeading: CLLocationDirection?
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
    private var mapHeadingFilter = RideMapHeadingFilter()

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
            mapHeading: mapLocation.flatMap { mapHeadingFilter.update(with: $0) },
            speedInMilesPerHour: speed
        )
    }

    func processStationary() -> RideSpeedUpdate {
        filteredSpeed = 0
        lastAcceptedSample = nil

        return RideSpeedUpdate(
            mapLocation: nil,
            mapHeading: nil,
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
