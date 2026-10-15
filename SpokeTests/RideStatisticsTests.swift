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

    @Test func includesCurrentMonthAndRejectsActiveAndFutureRides() {
        let now = date(14)
        let boundary = date(1, hour: 0)
        let active = TrackedRide(startedAt: date(13))
        let unfinishedInThisSnapshot = ride(at: now.addingTimeInterval(-100), duration: 200)
        let stats = RideStatistics(rides: [
            ride(at: boundary), ride(at: boundary.addingTimeInterval(-1)),
            ride(at: now.addingTimeInterval(-600)), ride(at: date(15)),
            active, unfinishedInThisSnapshot,
        ], now: now, calendar: calendar)

        #expect(stats.startDate == boundary)
        #expect(stats.endDate == date(15, hour: 0))
        #expect(stats.days.count == 14)
        #expect(stats.rideCount == 2)
        #expect(stats.activeDays == 2)
        #expect(stats.days.first?.date == boundary)
        #expect(stats.days.last?.date == date(14, hour: 0))
        #expect(abs((stats.topSpeed ?? 0) - 41.5024) < 0.01)
        #expect(stats.longestDuration == 600)
    }

    @Test func peakSpeedUsesTheFastestSegmentAndLongestTimeExcludesPauses() {
        let steady = ride(at: date(13), duration: 1_800)
        let sprint = ride(at: date(12), duration: 3_600)
        sprint.routePoints.append(RideRoutePoint(
            latitude: 0, longitude: 0.02, horizontalAccuracy: 5,
            recordedAt: sprint.startedAt.addingTimeInterval(180)
        ))
        let paused = ride(at: date(11), duration: 7_200, withRoute: false)
        paused.accumulatedPausedDuration = 6_000
        let stats = RideStatistics(rides: [steady, sprint, paused], now: date(14), calendar: calendar)

        #expect(abs((stats.topSpeed ?? 0) - 27.6683) < 0.01)
        #expect(abs((stats.fastestRide ?? 0) - 13.8341) < 0.01)
        #expect(stats.longestDuration == 3_600)
    }

    @Test func peakRecordsExcludeOldActiveAndFutureRides() {
        let active = ride(at: date(13), duration: 60)
        active.endedAt = nil
        let stats = RideStatistics(rides: [
            ride(at: date(13), duration: 1_800),
            ride(at: date(14, month: 9), duration: 60),
            ride(at: date(15), duration: 60),
            ride(at: date(12, month: 9), duration: 7_200),
            active,
        ], now: date(14), calendar: calendar)

        #expect(abs((stats.topSpeed ?? 0) - 13.8341) < 0.01)
        #expect(stats.longestDuration == 1_800)
    }

    @Test func topSpeedRequiresTwoPointsWithDifferentTimestamps() {
        let recorded = ride(at: date(13), duration: 0)
        #expect(RideRouteSpeed.topSpeed(for: recorded.routePoints) == nil)
        #expect(RideRouteSpeed.topSpeed(for: Array(recorded.routePoints.prefix(1))) == nil)

        let stopped = ride(at: date(13))
        stopped.routePoints[1].longitude = 0
        #expect(RideRouteSpeed.topSpeed(for: stopped.routePoints) == 0)
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
            #expect(stats.topSpeed == nil)
            #expect(stats.longestDuration == (rides.isEmpty ? nil : 600))
            #expect(stats.days.count == 14)
            #expect(stats.days.allSatisfy { $0.averageSpeed == nil && $0.distanceInMeters == 0 })
        }
    }

    @Test func calendarDaysRemainCorrectAcrossDaylightSavingAndYearBoundaries() {
        for now in [date(15, month: 3), date(10, month: 11), date(10, month: 1, year: 2027)] {
            let stats = RideStatistics(rides: [], now: now, calendar: calendar)
            let count = calendar.component(.day, from: now)
            #expect(stats.days.count == count)
            #expect(Set(stats.days.map(\.date)).count == count)
            #expect(stats.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
            #expect(calendar.dateComponents([.day], from: stats.startDate, to: stats.endDate).day == count)
        }
    }

    @Test func recordsRetainTheirRidesAndResolveTiesToTheLatestRide() {
        let earlier = ride(at: date(12), duration: 600)
        let latest = ride(at: date(13), duration: 600)
        let longestTime = ride(at: date(11), duration: 1_800, withRoute: false)
        let stats = RideStatistics(rides: [latest, earlier, longestTime], now: date(14), calendar: calendar)
        #expect(stats.longestDistanceRide === latest)
        #expect(stats.fastestAverageRide === latest)
        #expect(stats.topSpeedRide === latest)
        #expect(stats.longestTimeRide === longestTime)
        let empty = RideStatistics(rides: [], now: date(14), calendar: calendar)
        #expect(empty.longestDistanceRide == nil)
        #expect(empty.fastestAverageRide == nil)
    }

    @Test func weeklyCalendarRespectsFirstWeekdayAndIncludesDaysWithoutRoutes() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let stats = RideStatistics(rides: [ride(at: date(13), withRoute: false)], now: date(14), calendar: mondayFirst)
        #expect(stats.calendarLeadingDays == 3)
        #expect(stats.weekdaySymbols.first == mondayFirst.veryShortStandaloneWeekdaySymbols[1])
        #expect(stats.days.first { $0.date == date(13, hour: 0) }?.rideCount == 1)
        #expect(stats.days.filter { $0.rideCount > 0 }.count == stats.activeDays)
        #expect(stats.days.reduce(0) { $0 + $1.rideCount } == stats.rideCount)
    }

    @Test func periodsFilterTotalsRecordsAndActivityTogether() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let lastYear = ride(at: date(20, month: 12, year: 2025), duration: 120)
        let lastMonth = ride(at: date(20, month: 9), duration: 240)
        let lastWeek = ride(at: date(1), duration: 360)
        let thisWeek = ride(at: date(13), duration: 480)
        let rides = [lastYear, lastMonth, lastWeek, thisWeek]
        let expectations: [(RideStatisticsPeriod, Int, Date, TrackedRide, TimeInterval)] = [
            (.allTime, 4, date(20, month: 12, year: 2025, hour: 0), lastYear, 1_200),
            (.thisYear, 3, date(1, month: 1, hour: 0), lastMonth, 1_080),
            (.thisMonth, 2, date(1, hour: 0), lastWeek, 840),
            (.thisWeek, 1, date(12, hour: 0), thisWeek, 480),
        ]
        for (period, count, start, fastest, duration) in expectations {
            let stats = RideStatistics(rides: rides, period: period, now: date(14), calendar: mondayFirst)
            #expect(stats.startDate == start)
            #expect(stats.rideCount == count)
            #expect(stats.activeDays == count)
            #expect(stats.days.reduce(0) { $0 + $1.rideCount } == count)
            #expect(stats.duration == duration)
            #expect(stats.fastestAverageRide === fastest)
            #expect(abs(stats.distanceInMeters - Double(count) * RideMetrics.distanceInMeters(for: thisWeek)) < 0.001)
        }
    }

    @Test func allTimeStartsAtEarliestValidCompletedRideAndHandlesEmptyHistory() {
        let active = TrackedRide(startedAt: date(1, year: 2000))
        let invalid = ride(at: date(1, year: 2001), duration: -60)
        let earliest = ride(at: date(29, month: 2, year: 2024))
        let future = ride(at: date(15))
        let stats = RideStatistics(rides: [active, invalid, future, earliest], period: .allTime, now: date(14), calendar: calendar)
        #expect(stats.startDate == date(29, month: 2, year: 2024, hour: 0))
        #expect(stats.rideCount == 1)
        let empty = RideStatistics(rides: [active, invalid, future], period: .allTime, now: date(14), calendar: calendar)
        #expect(empty.days.count == 1)
        #expect(empty.startDate == date(14, hour: 0))
        #expect(empty.rideCount == 0)
    }

    @Test func speedDistributionAndMotionUseTheSelectedPeriod() {
        let rides = [ride(at: date(30, month: 9), duration: 20), ride(at: date(13), duration: 20)]
        let month = RideStatistics(rides: rides, period: .thisMonth, now: date(14), calendar: calendar)
        let year = RideStatistics(rides: rides, period: .thisYear, now: date(14), calendar: calendar)
        #expect(month.timeBreakdown.recorded == 20)
        #expect(year.timeBreakdown.recorded == 40)
        #expect(month.timeBreakdown.moving == 20)
        #expect(year.timeBreakdown.secondsByBand.reduce(0, +) == 40)
    }

    @Test func weekUsesLocalFirstWeekdayAcrossYearAndDaylightSavingBoundaries() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let newYear = RideStatistics(rides: [], period: .thisWeek, now: date(1, month: 1, year: 2027), calendar: mondayFirst)
        #expect(newYear.startDate == date(28, month: 12, hour: 0))
        #expect(newYear.days.count == 5)
        let daylightSaving = RideStatistics(rides: [], period: .thisWeek, now: date(8, month: 3), calendar: mondayFirst)
        #expect(daylightSaving.days.count == 7)
        #expect(daylightSaving.endDate.timeIntervalSince(daylightSaving.startDate) == 7 * 86_400 - 3_600)
        let leapMonth = RideStatistics(rides: [], period: .thisMonth, now: date(29, month: 2, year: 2024), calendar: calendar)
        #expect(leapMonth.days.count == 29)
    }
}
