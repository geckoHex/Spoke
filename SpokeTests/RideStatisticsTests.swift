import Foundation
import Testing
@testable import Spoke

struct RideStatisticsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func ride(at start: Date, duration: TimeInterval = 600, withRoute: Bool = true) -> TrackedRide {
        let ride = TrackedRide(startedAt: start)
        ride.end(at: start.addingTimeInterval(duration))
        if withRoute {
            ride.routePoints = [
                RideRoutePoint(latitude: 0, longitude: 0, horizontalAccuracy: 5, recordedAt: start),
                RideRoutePoint(latitude: 0, longitude: 0.1, horizontalAccuracy: 5, recordedAt: start.addingTimeInterval(duration)),
            ]
        }
        return ride
    }

    @Test func weightsSpeedByRidingTimeAndGroupsMultipleRidesOnTheSameDay() {
        let stats = RideStatistics(rides: [
            ride(at: date(13), duration: 600),
            ride(at: date(13, hour: 14), duration: 1_800),
        ], now: date(14), calendar: calendar)

        #expect(stats.rideCount == 2)
        #expect(stats.activeDays == 1)
        #expect(stats.duration == 2_400)
        #expect(stats.averageDuration == 1_200)
        #expect(abs((stats.averageSpeed ?? 0) - 20.7512) < 0.01)
        #expect(abs((stats.fastestRide ?? 0) - 41.5024) < 0.01)
        #expect(abs((stats.longestRide ?? 0) - 11_131.949) < 0.1)
        #expect(stats.averageDistance == stats.longestRide)
        #expect(stats.days.filter { $0.averageSpeed != nil }.count == 1)
        #expect(stats.days.first { $0.averageSpeed != nil }?.averageSpeed == stats.averageSpeed)
        #expect(abs(stats.days.reduce(0) { $0 + $1.distanceInMeters } - stats.distanceInMeters) < 0.001)
    }

    @Test func includesThirtyCalendarDaysAndRejectsActiveAndFutureRides() {
        let now = date(14)
        let boundary = date(15, month: 9, hour: 0)
        let active = TrackedRide(startedAt: date(13))
        let unfinishedInThisSnapshot = ride(at: now.addingTimeInterval(-100), duration: 200)
        let stats = RideStatistics(rides: [
            ride(at: boundary), ride(at: boundary.addingTimeInterval(-1)),
            ride(at: now.addingTimeInterval(-600)), ride(at: date(15)),
            active, unfinishedInThisSnapshot,
        ], now: now, calendar: calendar)

        #expect(stats.startDate == boundary)
        #expect(stats.endDate == date(15, hour: 0))
        #expect(stats.days.count == 30)
        #expect(stats.rideCount == 2)
        #expect(stats.activeDays == 2)
        #expect(stats.days.first?.date == boundary)
        #expect(stats.days.last?.date == date(14, hour: 0))
    }

    @Test func excludesPausedTimeAndDoesNotTreatMissingRoutesAsZeroSpeed() {
        let recorded = ride(at: date(13), duration: 1_800)
        recorded.accumulatedPausedDuration = 1_200
        let missingRoute = ride(at: date(12), duration: 3_600, withRoute: false)
        let zeroDuration = ride(at: date(11), duration: 0)
        let stats = RideStatistics(rides: [recorded, missingRoute, zeroDuration], now: date(14), calendar: calendar)

        #expect(stats.rideCount == 3)
        #expect(stats.duration == 4_200)
        #expect(abs((stats.averageSpeed ?? 0) - 41.5024) < 0.01)
        #expect(stats.days.first { $0.date == date(12, hour: 0) }?.averageSpeed == nil)
        #expect(stats.days.first { $0.date == date(11, hour: 0) }?.averageSpeed == nil)
    }

    @Test func emptyHistoryAndRidesWithoutRoutesHaveNoSpeedOrRecords() {
        for rides in [[], [ride(at: date(13), withRoute: false)]] {
            let stats = RideStatistics(rides: rides, now: date(14), calendar: calendar)
            #expect(stats.distanceInMeters == 0)
            #expect(stats.averageSpeed == nil)
            #expect(stats.longestRide == nil)
            #expect(stats.fastestRide == nil)
            #expect(stats.days.count == 30)
            #expect(stats.days.allSatisfy { $0.averageSpeed == nil && $0.distanceInMeters == 0 })
        }
    }

    @Test func calendarDaysRemainCorrectAcrossDaylightSavingAndYearBoundaries() {
        for now in [date(15, month: 3), date(10, month: 11), date(10, month: 1, year: 2027)] {
            let stats = RideStatistics(rides: [], now: now, calendar: calendar)
            #expect(stats.days.count == 30)
            #expect(Set(stats.days.map(\.date)).count == 30)
            #expect(stats.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
            #expect(calendar.dateComponents([.day], from: stats.startDate, to: stats.endDate).day == 30)
        }
    }
}
