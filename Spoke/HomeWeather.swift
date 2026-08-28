//
//  HomeWeather.swift
//  Spoke
//

import CoreLocation
import Foundation
import Observation
import WeatherKit

struct HomeWeatherSnapshot: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let temperature: String
    let condition: String
    let symbolName: String
    let attributionMarkURL: URL
    let legalPageURL: URL
}

struct HomeWeatherCache {
    static let duration: TimeInterval = 20 * 60

    private let defaults: UserDefaults
    private let key: String
    private let lastRequestKey: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "homeWeatherSnapshot"
    ) {
        self.defaults = defaults
        self.key = key
        lastRequestKey = "\(key).lastRequestAt"
    }

    func storedSnapshot() -> HomeWeatherSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HomeWeatherSnapshot.self, from: data)
    }

    func freshSnapshot(at date: Date = .now) -> HomeWeatherSnapshot? {
        guard let snapshot = storedSnapshot(),
              date.timeIntervalSince(snapshot.fetchedAt) < Self.duration
        else { return nil }

        return snapshot
    }

    func save(_ snapshot: HomeWeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func canRequest(at date: Date = .now) -> Bool {
        guard let lastRequestAt = defaults.object(forKey: lastRequestKey) as? Date
        else { return true }

        return date.timeIntervalSince(lastRequestAt) >= Self.duration
    }

    func recordRequest(at date: Date = .now) {
        defaults.set(date, forKey: lastRequestKey)
    }

    func nextRequestDate() -> Date? {
        guard let lastRequestAt = defaults.object(forKey: lastRequestKey) as? Date
        else { return nil }

        return lastRequestAt.addingTimeInterval(Self.duration)
    }
}

@MainActor
@Observable
final class HomeWeatherModel {
    private(set) var snapshot: HomeWeatherSnapshot?
    private(set) var isLoading = false
    private(set) var isUnavailable = false

    @ObservationIgnored private let cache: HomeWeatherCache

    init() {
        let cache = HomeWeatherCache()
        self.cache = cache
        snapshot = cache.storedSnapshot()
    }

    init(cache: HomeWeatherCache) {
        self.cache = cache
        snapshot = cache.storedSnapshot()
    }

    func maintainWeather() async {
        while !Task.isCancelled {
            let shouldScheduleRefresh = await loadIfNeeded()

            guard shouldScheduleRefresh,
                  let nextRequestDate = cache.nextRequestDate()
            else { return }
            let delay = max(nextRequestDate.timeIntervalSinceNow, 1)

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    @discardableResult
    func loadIfNeeded(at date: Date = .now) async -> Bool {
        if let cachedSnapshot = cache.freshSnapshot(at: date) {
            snapshot = cachedSnapshot
            isUnavailable = false
            return true
        }

        guard cache.canRequest(at: date) else {
            isUnavailable = snapshot == nil
            return true
        }

        guard !isLoading else { return true }

        isLoading = true
        isUnavailable = false
        defer { isLoading = false }
        var didStartRequest = false

        do {
            let location = try await Self.currentLocation()
            let requestDate = Date.now
            cache.recordRequest(at: requestDate)
            didStartRequest = true
            async let currentWeather = WeatherService.shared.weather(
                for: location,
                including: .current
            )
            async let attribution = WeatherService.shared.attribution
            let (weather, weatherAttribution) = try await (
                currentWeather,
                attribution
            )

            let updatedSnapshot = HomeWeatherSnapshot(
                fetchedAt: requestDate,
                temperature: weather.temperature.formatted(
                    .measurement(width: .abbreviated, usage: .weather)
                ),
                condition: weather.condition.description,
                symbolName: weather.symbolName,
                attributionMarkURL: weatherAttribution.combinedMarkDarkURL,
                legalPageURL: weatherAttribution.legalPageURL
            )

            cache.save(updatedSnapshot)
            snapshot = updatedSnapshot
            return true
        } catch is CancellationError {
            return false
        } catch {
            isUnavailable = snapshot == nil
            return didStartRequest
        }
    }

    nonisolated private static func currentLocation() async throws -> CLLocation {
        for try await update in CLLocationUpdate.liveUpdates(.default) {
            try Task.checkCancellation()

            if update.authorizationDenied
                || update.authorizationDeniedGlobally
                || update.authorizationRestricted
            {
                throw HomeWeatherError.locationUnavailable
            }

            if let location = update.location {
                return location
            }
        }

        throw HomeWeatherError.locationUnavailable
    }
}

private enum HomeWeatherError: Error {
    case locationUnavailable
}
