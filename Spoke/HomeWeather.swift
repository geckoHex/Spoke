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
    let windSpeed: String?
    let windDirection: String?
    let attributionMarkURL: URL
    let legalPageURL: URL

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) >= HomeWeatherCache.duration
    }
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
              !snapshot.isStale(at: date)
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

    func invalidate() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: lastRequestKey)
    }
}

@MainActor
@Observable
final class HomeWeatherModel {
    private(set) var snapshot: HomeWeatherSnapshot?
    private(set) var isLoading = false
    private(set) var isUnavailable = false

    @ObservationIgnored private let cache: HomeWeatherCache

    @ObservationIgnored private let fetch: () async throws -> HomeWeatherSnapshot

    init(
        cache: HomeWeatherCache? = nil,
        fetch: @escaping () async throws -> HomeWeatherSnapshot = { try await HomeWeatherModel.fetchSnapshot() }
    ) {
        let cache = cache ?? HomeWeatherCache()
        self.cache = cache
        self.fetch = fetch
        snapshot = cache.storedSnapshot()
    }

    func refresh() async {
        _ = await loadIfNeeded(forceRefresh: true)
    }

    func maintainWeather() async {
        while !Task.isCancelled {
            guard await loadIfNeeded(), let nextRequestDate = cache.nextRequestDate() else { return }
            do {
                try await Task.sleep(for: .seconds(max(nextRequestDate.timeIntervalSinceNow, 1)))
            } catch {
                return
            }
        }
    }

    @discardableResult
    func loadIfNeeded(at date: Date = .now, forceRefresh: Bool = false) async -> Bool {
        guard !isLoading else { return true }
        if !forceRefresh {
            if let cachedSnapshot = cache.freshSnapshot(at: date) {
                snapshot = cachedSnapshot
                return true
            }
            guard cache.canRequest(at: date) else { return true }
        }

        isLoading = true
        defer { isLoading = false }
        cache.recordRequest(at: date)
        do {
            let updatedSnapshot = try await fetch()
            cache.save(updatedSnapshot)
            snapshot = updatedSnapshot
            isUnavailable = false
            return true
        } catch is CancellationError {
            return false
        } catch {
            isUnavailable = true
            return true
        }
    }

    private static func fetchSnapshot() async throws -> HomeWeatherSnapshot {
        let location = try await Self.currentLocation()
        let requestDate = Date.now
        async let currentWeather = WeatherService.shared.weather(
            for: location,
            including: .current
        )
        async let attribution = WeatherService.shared.attribution
        let (weather, weatherAttribution) = try await (
            currentWeather,
            attribution
        )

        return HomeWeatherSnapshot(
            fetchedAt: requestDate,
            temperature: weather.temperature.formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .weather,
                    numberFormatStyle: .number.precision(.fractionLength(0))
                )
            ),
            condition: weather.condition.description,
            symbolName: weather.symbolName,
            windSpeed: weather.wind.speed.formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .wind,
                    numberFormatStyle: .number.precision(.fractionLength(0))
                )
            ),
            windDirection: weather.wind.compassDirection.abbreviation,
            attributionMarkURL: weatherAttribution.combinedMarkDarkURL,
            legalPageURL: weatherAttribution.legalPageURL
        )
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
