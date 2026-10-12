import Foundation
import Testing
@testable import Spoke

@MainActor
struct HomeWeatherBackgroundTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let midnight = Date(timeIntervalSince1970: 0)

    @Test func selectsImageAtEveryBoundary() {
        let cases: [(TimeInterval, String)] = [
            (0, "WeatherNight"),
            (390 * 60 - 1, "WeatherNight"),
            (390 * 60, "WeatherSunrise"),
            (435 * 60 - 1, "WeatherSunrise"),
            (435 * 60, "WeatherMorning"),
            (720 * 60 - 1, "WeatherMorning"),
            (720 * 60, "WeatherAfternoon"),
            (1_050 * 60 - 1, "WeatherAfternoon"),
            (1_050 * 60, "WeatherSunset"),
            (1_095 * 60 - 1, "WeatherSunset"),
            (1_095 * 60, "WeatherEvening"),
            (1_215 * 60 - 1, "WeatherEvening"),
            (1_215 * 60, "WeatherNight"),
            (24 * 60 * 60 - 1, "WeatherNight")
        ]
        for (seconds, expected) in cases {
            #expect(HomeWeatherBackground.imageName(
                at: midnight.addingTimeInterval(seconds),
                sunrise: midnight.addingTimeInterval(7 * 60 * 60),
                sunset: midnight.addingTimeInterval(18 * 60 * 60),
                calendar: calendar
            ) == expected)
        }
    }

    @Test func solarWindowsFollowWeatherRatherThanFixedHours() {
        #expect(HomeWeatherBackground.imageName(
            at: midnight.addingTimeInterval(5 * 60 * 60),
            sunrise: midnight.addingTimeInterval(5 * 60 * 60 + 15 * 60),
            sunset: midnight.addingTimeInterval(21 * 60 * 60),
            calendar: calendar
        ) == "WeatherSunrise")
        #expect(HomeWeatherBackground.imageName(
            at: midnight.addingTimeInterval(21 * 60 * 60),
            sunrise: midnight.addingTimeInterval(5 * 60 * 60 + 15 * 60),
            sunset: midnight.addingTimeInterval(21 * 60 * 60),
            calendar: calendar
        ) == "WeatherSunset")
    }

    @Test func missingAndPreviousDaySolarEventsUseLocalClock() {
        let noon = midnight.addingTimeInterval(12 * 60 * 60)
        #expect(HomeWeatherBackground.imageName(
            at: noon, sunrise: nil, sunset: nil, calendar: calendar
        ) == "WeatherAfternoon")
        #expect(HomeWeatherBackground.imageName(
            at: noon,
            sunrise: midnight.addingTimeInterval(-17 * 60 * 60),
            sunset: midnight.addingTimeInterval(-6 * 60 * 60),
            calendar: calendar
        ) == "WeatherAfternoon")

        var localCalendar = calendar
        localCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        #expect(HomeWeatherBackground.imageName(
            at: noon, sunrise: nil, sunset: nil, calendar: localCalendar
        ) == "WeatherNight")
    }

    @Test func cachedWeatherWithoutSolarEventsStillDecodes() throws {
        let data = Data("""
        {"fetchedAt":0,"temperature":"72°F","condition":"Clear","symbolName":"sun.max",
         "attributionMarkURL":"https://example.com/mark","legalPageURL":"https://example.com/legal"}
        """.utf8)
        let snapshot = try JSONDecoder().decode(HomeWeatherSnapshot.self, from: data)
        #expect(snapshot.temperature == "72°F")
        #expect(snapshot.sunrise == nil)
        #expect(snapshot.sunset == nil)
    }
}
