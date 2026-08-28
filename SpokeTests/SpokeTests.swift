//
//  SpokeTests.swift
//  SpokeTests
//
//  Created by Beck Orion on 8/27/26.
//

import Foundation
import SwiftData
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

    @MainActor
    @Test func spotifyHistoryLogsOnlyWhenTheTrackChanges() throws {
        let schema = Schema([
            TrackedRide.self,
            RideRoutePoint.self,
            RideSoundtrackEntry.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let controller = RideSessionController()
        controller.configure(modelContext: container.mainContext)

        let rideStart = Date(timeIntervalSince1970: 10_000)
        let ride = try #require(controller.startRide(at: rideStart))
        let firstTrack = SpotifyTrack(
            spotifyID: "first-track",
            albumArtURL: nil,
            title: "First Song",
            artist: "First Artist",
            progress: 30,
            duration: 180,
            isPlaying: true,
            receivedAt: rideStart.addingTimeInterval(60)
        )
        let sameTrackAtNextCheck = SpotifyTrack(
            spotifyID: "first-track",
            albumArtURL: nil,
            title: "First Song",
            artist: "First Artist",
            progress: 40,
            duration: 180,
            isPlaying: true,
            receivedAt: rideStart.addingTimeInterval(70)
        )
        let secondTrack = SpotifyTrack(
            spotifyID: "second-track",
            albumArtURL: nil,
            title: "Second Song",
            artist: "Second Artist",
            progress: 5,
            duration: 200,
            isPlaying: true,
            receivedAt: rideStart.addingTimeInterval(100)
        )

        controller.recordSpotifyCheck(firstTrack)
        controller.recordSpotifyCheck(sameTrackAtNextCheck)
        controller.recordSpotifyCheck(secondTrack)

        let entries = ride.soundtrackEntries.sorted { $0.startedAt < $1.startedAt }
        #expect(entries.count == 2)
        #expect(entries.first?.title == "First Song")
        #expect(entries.first?.startedAt == rideStart.addingTimeInterval(30))
        #expect(entries.last?.title == "Second Song")
    }
}
