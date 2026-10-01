import CoreLocation
import Foundation
import OSLog
import MapKit

// Adapts existing ride data into events; owns no location manager or distance algorithm.
@MainActor
final class LiveRideController {
    private let narrator = LiveRideNarrator()
    private var configuration = LiveRideConfiguration()
    private weak var ride: TrackedRide?
    private var isSuspended = false
    private var isRunning = false
    private var generation = UUID()
    private var timer: Task<Void, Never>?
    private var geocodingTask: Task<Void, Never>?
    private var geocodingRequest: MKReverseGeocodingRequest?
    private var latestLocation: CLLocation?
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodedAt: Date?
    private var street = LiveRidePlaceConfirmation()
    private var city = LiveRidePlaceConfirmation()
    private var distance = 0.0
    private var pointCount = 0
    private var progress = LiveRideProgress(distance: 0, duration: 0, now: .now)

    func configure(_ configuration: LiveRideConfiguration) {
        guard self.configuration != configuration else { return }
        stopResources()
        self.configuration = configuration
        narrator.configure(configuration)
        refreshActivity()
    }

    func start(_ ride: TrackedRide) {
        stopResources()
        self.ride = ride
        isSuspended = false
        refreshActivity()
    }

    func stop() {
        ride = nil
        stopResources()
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        refreshActivity()
    }

    func refreshActivity() {
        let shouldRun = configuration.enabled && ride?.endedAt == nil
            && ride != nil && ride?.isPaused == false && !isSuspended
        guard shouldRun != isRunning else { return }
        stopResources()
        guard shouldRun, let ride else { return }
        isRunning = true
        distance = RideMetrics.distanceInMeters(for: ride)
        pointCount = ride.routePoints.count
        progress = LiveRideProgress(distance: distance, duration: ride.elapsedDuration(), now: .now)
        narrator.reset(active: true)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    func receive(_ update: RideSpeedUpdate) {
        guard isRunning, let ride else { return }
        if let speed = update.speedInMilesPerHour {
            narrator.submit(.speedChanged(speed))
        }
        if ride.routePoints.count != pointCount {
            distance = RideMetrics.distanceInMeters(for: ride)
            pointCount = ride.routePoints.count
        }
        if let sample = update.mapLocation, (0...25).contains(sample.horizontalAccuracy) {
            let location = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            latestLocation = location
            resolvePlaceIfNeeded(location)
        }
        tick()
    }

    private func tick() {
        guard isRunning, let ride else { return }
        for event in progress.events(distance: distance, duration: ride.elapsedDuration(), now: .now) {
            narrator.submit(event)
        }
        narrator.tick()
    }

    private func stopResources() {
        isRunning = false
        generation = UUID()
        timer?.cancel()
        timer = nil
        geocodingTask?.cancel()
        geocodingTask = nil
        geocodingRequest?.cancel()
        geocodingRequest = nil
        latestLocation = nil
        lastGeocodedLocation = nil
        lastGeocodedAt = nil
        street = LiveRidePlaceConfirmation()
        city = LiveRidePlaceConfirmation()
        narrator.reset(active: false)
    }

    private func resolvePlaceIfNeeded(_ location: CLLocation) {
        let wantsStreets = configuration.categories.contains(.streets)
        let wantsCities = configuration.categories.contains(.cities)
        guard wantsStreets || wantsCities, geocodingTask == nil,
              lastGeocodedAt.map({ Date.now.timeIntervalSince($0) >= 6 }) ?? true,
              lastGeocodedLocation.map({ location.distance(from: $0) >= 20 }) ?? true,
              let request = MKReverseGeocodingRequest(location: location) else { return }
        lastGeocodedAt = .now
        lastGeocodedLocation = location
        geocodingRequest = request
        request.preferredLocale = Locale(identifier: "en_US")
        let generation = generation
        let observedAt = Date.now
        geocodingTask = Task { [weak self] in
            do {
                let items = try await request.mapItems
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                defer {
                    self.geocodingTask = nil
                    self.geocodingRequest = nil
                }
                guard Date.now.timeIntervalSince(observedAt) <= 6,
                      let latestLocation = self.latestLocation,
                      latestLocation.distance(from: location) <= 60,
                      let item = items.first else {
                    LiveRidePolicy.logger.debug("PLACE → EXPIRED OR UNAVAILABLE")
                    return
                }
                let place = RideAddressResolver.liveRidePlace(from: item)
                if wantsStreets {
                    if place.street != self.street.confirmed { self.narrator.invalidate(.streets) }
                    if let name = self.street.observe(place.street, at: observedAt, isCity: false) {
                        self.narrator.submit(.streetChanged(name), at: observedAt)
                    }
                }
                if wantsCities {
                    if place.city != self.city.confirmed { self.narrator.invalidate(.cities) }
                    if let name = self.city.observe(place.city, at: observedAt, isCity: true) {
                        self.narrator.submit(.enteredCity(name), at: observedAt)
                    }
                }
                LiveRidePolicy.logger.debug("PLACE → OBSERVED; WAITING FOR CONFIRMATION OR UNCHANGED")
            } catch {
                guard let self, self.generation == generation else { return }
                self.geocodingTask = nil
                self.geocodingRequest = nil
                LiveRidePolicy.logger.debug("PLACE → GEOCODING UNAVAILABLE: \(error.localizedDescription)")
            }
        }
    }
}
