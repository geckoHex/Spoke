import Foundation

enum RideStatisticsPeriod: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case thisYear = "This Year"
    case thisMonth = "This Month"
    case thisWeek = "This Week"

    var id: Self { self }

    func startDate(now: Date, earliestRide: Date?, calendar: Calendar) -> Date {
        switch self {
        case .allTime:
            return calendar.startOfDay(for: earliestRide ?? now)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)!.start
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)!.start
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)!.start
        }
    }
}
