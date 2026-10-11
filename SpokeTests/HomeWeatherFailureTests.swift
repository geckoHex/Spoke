import Foundation
import Testing
@testable import Spoke

@MainActor
struct HomeWeatherFailureTests {
    @Test func failedRefreshKeepsOldWeatherAndAllowsImmediateRetry() async throws {
        let suite = "SpokeTests.WeatherFailure.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = HomeWeatherCache(defaults: defaults)
        let now = Date.now
        func snapshot(at date: Date) -> HomeWeatherSnapshot {
            HomeWeatherSnapshot(fetchedAt: date, temperature: "72°F", condition: "Clear",
                symbolName: "sun.max", windSpeed: nil, windDirection: nil,
                attributionMarkURL: URL(string: "https://example.com/mark")!,
                legalPageURL: URL(string: "https://example.com/legal")!)
        }
        let old = snapshot(at: now.addingTimeInterval(-1_200))
        cache.save(old)
        var shouldFail = true
        var requests = 0
        let model = HomeWeatherModel(cache: cache) {
            requests += 1
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return snapshot(at: now)
        }
        #expect(old.isStale(at: now))
        await model.loadIfNeeded(at: now)
        #expect(model.snapshot == old)
        #expect(cache.storedSnapshot() == old)
        #expect(model.isUnavailable)
        #expect(!model.isLoading)
        await model.loadIfNeeded(at: now)
        #expect(requests == 1)
        #expect(model.isUnavailable)
        shouldFail = false
        await model.refresh()
        #expect(requests == 2)
        #expect(!model.isUnavailable)
        #expect(model.snapshot?.isStale(at: now) == false)
    }
}
