import Foundation

struct RideStatistics {
    struct Day: Identifiable {
        let date: Date
        let distanceInMeters: Double
        let averageSpeed: Double?
        let rideCount: Int

        var id: Date { date }
    }

    private struct Ride {
        let model: TrackedRide
        let date: Date
        let distance: Double?
        let duration: TimeInterval
        let topSpeed: Double?
    }

    let startDate: Date
    let endDate: Date
    let days: [Day]
    let rideCount: Int
    let activeDays: Int
    let distanceInMeters: Double
    let duration: TimeInterval
    let averageSpeed: Double?
    let longestRide: Double?
    let fastestRide: Double?
    let topSpeed: Double?
    let longestDuration: TimeInterval?
    let longestDistanceRide: TrackedRide?
    let fastestAverageRide: TrackedRide?
    let topSpeedRide: TrackedRide?
    let longestTimeRide: TrackedRide?
    let timeBreakdown: RideTimeBreakdown
    let calendarLeadingDays: Int
    let weekdaySymbols: [String]

    var averageDistance: Double { rideCount > 0 ? distanceInMeters / Double(rideCount) : 0 }
    var averageDuration: TimeInterval { rideCount > 0 ? duration / Double(rideCount) : 0 }

    init(rides: [TrackedRide], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        startDate = start
        endDate = calendar.date(byAdding: .day, value: 1, to: today)!
        calendarLeadingDays = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        weekdaySymbols = (0..<7).map { calendar.veryShortStandaloneWeekdaySymbols[($0 + calendar.firstWeekday - 1) % 7] }

        let completed = rides.compactMap { ride -> Ride? in
            guard let endedAt = ride.endedAt,
                  ride.startedAt >= start, ride.startedAt <= now,
                  endedAt >= ride.startedAt, endedAt <= now
            else { return nil }

            return Ride(
                model: ride,
                date: calendar.startOfDay(for: ride.startedAt),
                distance: ride.routePoints.count > 1 ? RideMetrics.distanceInMeters(for: ride) : nil,
                duration: ride.elapsedDuration(),
                topSpeed: RideRouteSpeed.topSpeed(for: ride.routePoints)
            )
        }
        let byDay = Dictionary(grouping: completed, by: \.date)
        days = (0..<30).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let rides = byDay[date] ?? []
            return Day(
                date: date,
                distanceInMeters: rides.reduce(0) { $0 + ($1.distance ?? 0) },
                averageSpeed: Self.averageSpeed(for: rides),
                rideCount: rides.count
            )
        }
        rideCount = completed.count
        activeDays = byDay.count
        distanceInMeters = completed.reduce(0) { $0 + ($1.distance ?? 0) }
        duration = completed.reduce(0) { $0 + $1.duration }
        averageSpeed = Self.averageSpeed(for: completed)
        longestRide = completed.compactMap(\.distance).max()
        fastestRide = completed.compactMap { Self.averageSpeed(for: [$0]) }.max()
        topSpeed = completed.compactMap(\.topSpeed).max()
        longestDuration = completed.map(\.duration).max()
        longestDistanceRide = Self.record(in: completed, value: { $0.distance })
        fastestAverageRide = Self.record(in: completed, value: { Self.averageSpeed(for: [$0]) })
        topSpeedRide = Self.record(in: completed, value: { $0.topSpeed })
        longestTimeRide = Self.record(in: completed, value: { $0.duration })
        timeBreakdown = RideTimeBreakdown(rides: completed.map(\.model))
    }

    private static func record(in rides: [Ride], value: (Ride) -> Double?) -> TrackedRide? {
        let candidates: [(ride: TrackedRide, value: Double)] = rides.compactMap { ride in
            guard let measured = value(ride) else { return nil }
            return (ride.model, measured)
        }
        return candidates.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.ride.startedAt < rhs.ride.startedAt }
            return lhs.value < rhs.value
        }?.ride
    }

    private static func averageSpeed(for rides: [Ride]) -> Double? {
        // A ride without a timed route cannot contribute a measured speed.
        let timedRoutes = rides.filter { $0.distance != nil && $0.duration > 0 }
        let duration = timedRoutes.reduce(0) { $0 + $1.duration }
        guard duration > 0 else { return nil }
        let distance = timedRoutes.reduce(0) { $0 + ($1.distance ?? 0) }
        return distance / 1_609.344 / (duration / 3_600)
    }
}
