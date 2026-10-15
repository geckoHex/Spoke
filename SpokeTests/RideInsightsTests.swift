import CoreLocation
import Foundation
import Testing
@testable import Spoke

@MainActor
struct RideInsightsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func ride(_ intervals: [(speed: Double, seconds: Double)], at date: Date? = nil) -> TrackedRide {
        let date = date ?? start
        let ride = TrackedRide(startedAt: date)
        var elapsed = 0.0
        var meters = 0.0
        func point() -> RideRoutePoint {
            let point = RideRoutePoint(latitude: 0, longitude: meters / 111_319.490_793,
                                      horizontalAccuracy: 5, recordedAt: date.addingTimeInterval(elapsed))
            point.recordingStartedAt = date
            return point
        }
        ride.routePoints = [point()]
        for interval in intervals {
            elapsed += interval.seconds
            meters += interval.speed / 2.236_936_292_1 * interval.seconds
            ride.routePoints.append(point())
        }
        ride.end(at: date.addingTimeInterval(elapsed))
        return ride
    }

    @Test func speedBandsUseNonoverlappingBoundariesAndWeightByTime() {
        #expect([0.0, 4.99, 5, 9.99, 10, 14.99, 15, 30].map(RideSpeedBand.band(for:)) == [
            .underFive, .underFive, .fiveToTen, .fiveToTen,
            .tenToFifteen, .tenToFifteen, .fifteenPlus, .fifteenPlus,
        ])
        let time = RideTimeBreakdown(rides: [ride([(0, 10), (3, 20), (7, 5), (12, 25), (18, 10)])])
        #expect(time.secondsByBand == [30, 5, 25, 10])
        #expect(time.stopped == 10)
        #expect(time.moving == 60)
        #expect(time.secondsByBand.reduce(0, +) == time.recorded)
    }

    @Test func gapsPauseBoundariesAndPoorFixesDoNotBecomeStoppedTime() {
        let recorded = ride([(0, 10), (10, 60), (10, 10), (0, 10)])
        recorded.routePoints[3].recordingStartedAt = start.addingTimeInterval(75)
        recorded.routePoints[4].recordingStartedAt = start.addingTimeInterval(75)
        recorded.routePoints[4].horizontalAccuracy = 100
        recorded.accumulatedPausedDuration = 5
        let time = RideTimeBreakdown(rides: [recorded])
        #expect(time.recorded == 10)
        #expect(time.stopped == 10)
        #expect(time.moving == 0)

        for point in recorded.routePoints { point.recordingStartedAt = nil }
        #expect(RideTimeBreakdown(rides: [recorded]).recorded == 0)
        recorded.accumulatedPausedDuration = 0
        #expect(RideTimeBreakdown(rides: [recorded]).recorded == 20)
    }

    @Test func invalidTimesCoordinatesAndMissingRoutesAreIgnored() {
        let recorded = ride([(10, 10), (10, 10)])
        recorded.routePoints[1].latitude = .nan
        #expect(RideTimeBreakdown(rides: [recorded]).recorded == 0)
        recorded.routePoints[1].latitude = 0
        recorded.routePoints[1].recordedAt = start
        #expect(RideTimeBreakdown(rides: [recorded]).recorded == 20)
        recorded.endedAt = start.addingTimeInterval(5)
        #expect(RideTimeBreakdown(rides: [recorded]).recorded == 0)
        #expect(RideTimeBreakdown(rides: [TrackedRide(startedAt: start)]).recorded == 0)
    }

    @Test func explorationComparesAgainstOlderHistoryAndWorksInReverse() {
        let old = ride(Array(repeating: (15, 10), count: 10), at: start.addingTimeInterval(-40 * 86_400))
        let repeated = ride(Array(repeating: (15, 5), count: 20))
        let now = start.addingTimeInterval(1_000)
        let familiar = RideExploration(rides: [repeated, old], since: start, now: now)
        #expect(!familiar.paths.isEmpty)
        #expect(familiar.paths.allSatisfy { !$0.isNew })

        let longitudes = repeated.routePoints.map(\.longitude).reversed()
        for (point, longitude) in zip(repeated.routePoints, longitudes) { point.longitude = longitude }
        #expect(RideExploration(rides: [repeated, old], since: start, now: now).paths.allSatisfy { !$0.isNew })

        for point in repeated.routePoints { point.latitude += 0.002 }
        #expect(RideExploration(rides: [old, repeated], since: start, now: now).paths.allSatisfy { $0.isNew })
    }

    @Test func explorationHighlightsOnlyNewPortionsAndIgnoresGapsAndUnfinishedRides() {
        let old = ride(Array(repeating: (15, 10), count: 5), at: start.addingTimeInterval(-40 * 86_400))
        let extended = ride(Array(repeating: (15, 10), count: 10))
        let now = start.addingTimeInterval(1_000)
        let exploration = RideExploration(rides: [extended, old], since: start, now: now)
        #expect(exploration.paths.contains { $0.isNew })
        #expect(exploration.paths.contains { !$0.isNew })
        #expect(exploration.paths.count == 2)
        #expect(RideExploration(rides: [ride([(15, 60)])], since: start, now: now).paths.isEmpty)
        extended.endedAt = nil
        #expect(RideExploration(rides: [extended], since: start, now: now).paths.isEmpty)
        #expect(RideExploration(rides: [ride([(15, 10)], at: now)], since: start, now: now).paths.isEmpty)
    }
}
