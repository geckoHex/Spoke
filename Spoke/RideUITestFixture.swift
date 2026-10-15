import Foundation
import SwiftData

enum RideUITestFixture {
    static func insertStats(into context: ModelContext) throws {
        for offset in [1, 3, 4, 7, 9, 12, 14, 17, 20, 22, 25, 28] {
            let start = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            let ride = TrackedRide(startedAt: start)
            ride.end(at: start.addingTimeInterval(Double(30 + offset) * 60))
            context.insert(ride)
            for index in 0...1 {
                let point = RideRoutePoint(
                    latitude: 37, longitude: -122 + Double(index) * Double(10 + offset % 8) / 100,
                    horizontalAccuracy: 5,
                    recordedAt: index == 0 ? start : ride.endedAt!
                )
                context.insert(point)
                ride.routePoints.append(point)
            }
            ride.routeSummary = RideRouteSummary(points: ride.routePoints)
        }
        try context.save()
    }

    static func weatherModel() -> HomeWeatherModel {
        let suite = "SpokeUITests.Weather"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let cache = HomeWeatherCache(defaults: defaults)
        cache.save(HomeWeatherSnapshot(
            fetchedAt: .now.addingTimeInterval(-3_600), temperature: "72°F", condition: "Clear",
            symbolName: "sun.max", windSpeed: "8 mph", windDirection: "NW",
            attributionMarkURL: URL(fileURLWithPath: "/unavailable-weather-mark"),
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
            sunrise: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now),
            sunset: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)
        ))
        return HomeWeatherModel(cache: cache) { throw URLError(.notConnectedToInternet) }
    }

    static func insert(into context: ModelContext) throws {
        let ride = TrackedRide(startedAt: .now.addingTimeInterval(-3_600))
        ride.customName = "Morning Loop"
        ride.endedAt = ride.startedAt.addingTimeInterval(1_200)
        context.insert(ride)
        for (index, coordinate) in [
            (37.770, -122.450), (37.772, -122.450),
            (37.772, -122.448), (37.771, -122.447), (37.769, -122.449)
        ].enumerated() {
            let point = RideRoutePoint(
                latitude: coordinate.0, longitude: coordinate.1, horizontalAccuracy: 5,
                recordedAt: ride.startedAt.addingTimeInterval(Double(index) * 300)
            )
            context.insert(point)
            ride.routePoints.append(point)
        }
        ride.routeSummary = RideRouteSummary(points: ride.routePoints)
        try context.save()
    }
}
