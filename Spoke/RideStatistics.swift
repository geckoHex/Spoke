import Foundation

struct RideStatistics {
    struct Day: Identifiable {
        let date: Date
        let distanceInMeters: Double
        let averageSpeed: Double?

        var id: Date { date }
    }

    private struct Ride {
        let date: Date
        let distance: Double?
        let duration: TimeInterval
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

    var averageDistance: Double { rideCount > 0 ? distanceInMeters / Double(rideCount) : 0 }
    var averageDuration: TimeInterval { rideCount > 0 ? duration / Double(rideCount) : 0 }

    init(rides: [TrackedRide], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        startDate = start
        endDate = calendar.date(byAdding: .day, value: 1, to: today)!

        let completed = rides.compactMap { ride -> Ride? in
            guard let endedAt = ride.endedAt,
                  ride.startedAt >= start, ride.startedAt <= now,
                  endedAt >= ride.startedAt, endedAt <= now
            else { return nil }

            return Ride(
                date: calendar.startOfDay(for: ride.startedAt),
                distance: ride.routePoints.count > 1 ? RideMetrics.distanceInMeters(for: ride) : nil,
                duration: ride.elapsedDuration()
            )
        }
        let byDay = Dictionary(grouping: completed, by: \.date)
        days = (0..<30).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let rides = byDay[date] ?? []
            return Day(
                date: date,
                distanceInMeters: rides.reduce(0) { $0 + ($1.distance ?? 0) },
                averageSpeed: Self.averageSpeed(for: rides)
            )
        }
        rideCount = completed.count
        activeDays = byDay.count
        distanceInMeters = completed.reduce(0) { $0 + ($1.distance ?? 0) }
        duration = completed.reduce(0) { $0 + $1.duration }
        averageSpeed = Self.averageSpeed(for: completed)
        longestRide = completed.compactMap(\.distance).max()
        fastestRide = completed.compactMap { Self.averageSpeed(for: [$0]) }.max()
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
