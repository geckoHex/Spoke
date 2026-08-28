//
//  SpokeTests.swift
//  SpokeTests
//
//  Created by Beck Orion on 8/27/26.
//

import Foundation
import Testing
@testable import Spoke

struct SpokeTests {
    @Test func activeRideDurationExcludesCurrentPause() {
        let start = Date(timeIntervalSince1970: 1_000)
        let ride = TrackedRide(startedAt: start)

        ride.pause(at: start.addingTimeInterval(10))

        #expect(ride.elapsedDuration(at: start.addingTimeInterval(25)) == 10)
    }

    @Test func pausedRideIgnoresAStaleTimelineDate() {
        let start = Date(timeIntervalSince1970: 1_000)
        let ride = TrackedRide(startedAt: start)

        ride.pause(at: start.addingTimeInterval(10))

        #expect(ride.elapsedDuration(at: start.addingTimeInterval(9)) == 10)
    }

    @Test func completedRideDurationExcludesAllPausedTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        let ride = TrackedRide(startedAt: start)

        ride.pause(at: start.addingTimeInterval(10))
        ride.resume(at: start.addingTimeInterval(20))
        ride.end(at: start.addingTimeInterval(35))

        #expect(ride.elapsedDuration(at: start.addingTimeInterval(100)) == 25)
    }

    @Test func endingWhilePausedFreezesTheActiveDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let ride = TrackedRide(startedAt: start)

        ride.pause(at: start.addingTimeInterval(12))
        ride.end(at: start.addingTimeInterval(30))

        #expect(ride.elapsedDuration() == 12)
    }
}
