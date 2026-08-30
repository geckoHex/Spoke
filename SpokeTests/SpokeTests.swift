//
//  SpokeTests.swift
//  SpokeTests
//
//  Created by Beck Orion on 8/27/26.
//

import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Spoke

struct SpokeTests {
    @Test func speedAnnouncementOnlyResolvesBundledMilePerHourRange() {
        #expect(RideSpeedAnnouncer.resourceName(for: 0) == nil)
        #expect(RideSpeedAnnouncer.resourceName(for: 1) == "1")
        #expect(RideSpeedAnnouncer.resourceName(for: 13) == "13")
        #expect(RideSpeedAnnouncer.resourceName(for: 45) == "45")
        #expect(RideSpeedAnnouncer.resourceName(for: 46) == nil)
    }

    @Test func speedUsesItsOwnAccuracyRatherThanCoordinateAccuracy() async throws {
        let processor = RideSpeedProcessor()
        let now = Date(timeIntervalSince1970: 10_000)
        let sample = RideLocationSample(
            latitude: 0,
            longitude: 0,
            horizontalAccuracy: 250,
            speed: 8,
            speedAccuracy: 0.5,
            timestamp: now
        )

        let update = await processor.process([sample], now: now)

        #expect(update.speedInMilesPerHour == 18)
    }

    @Test func poorSpeedAccuracyIsStillRejected() async throws {
        let processor = RideSpeedProcessor()
        let now = Date(timeIntervalSince1970: 10_000)
        let sample = RideLocationSample(
            latitude: 0,
            longitude: 0,
            horizontalAccuracy: 5,
            speed: 8,
            speedAccuracy: 3.1,
            timestamp: now
        )

        let update = await processor.process([sample], now: now)

        #expect(update.speedInMilesPerHour == nil)
    }

    @Test func stationaryLocationEventClearsSpeedImmediately() async throws {
        let processor = RideSpeedProcessor()

        let update = await processor.processStationary()

        #expect(update.speedInMilesPerHour == 0)
    }

    @MainActor
    @Test func weatherCacheExpiresAfterTwentyMinutes() throws {
        let suiteName = "SpokeTests.WeatherCache.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = HomeWeatherCache(defaults: defaults)
        let fetchedAt = Date(timeIntervalSince1970: 10_000)
        let snapshot = HomeWeatherSnapshot(
            fetchedAt: fetchedAt,
            temperature: "72°F",
            condition: "Clear",
            symbolName: "sun.max.fill",
            attributionMarkURL: URL(string: "https://example.com/mark")!,
            legalPageURL: URL(string: "https://example.com/legal")!
        )
        cache.save(snapshot)
        cache.recordRequest(at: fetchedAt)

        #expect(
            cache.freshSnapshot(
                at: fetchedAt.addingTimeInterval(20 * 60 - 1)
            ) == snapshot
        )
        #expect(
            cache.freshSnapshot(
                at: fetchedAt.addingTimeInterval(20 * 60)
            ) == nil
        )
        #expect(
            !cache.canRequest(
                at: fetchedAt.addingTimeInterval(20 * 60 - 1)
            )
        )
        #expect(
            cache.canRequest(
                at: fetchedAt.addingTimeInterval(20 * 60)
            )
        )
        #expect(
            cache.nextRequestDate()
                == fetchedAt.addingTimeInterval(20 * 60)
        )

        cache.invalidate()

        #expect(cache.storedSnapshot() == nil)
        #expect(cache.canRequest(at: fetchedAt))
        #expect(cache.nextRequestDate() == nil)
    }

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

    @Test func rideRenameTrimsWhitespaceAndCanBeCleared() {
        let ride = TrackedRide()

        ride.rename(to: "  Morning Loop  ")
        #expect(ride.customName == "Morning Loop")

        ride.rename(to: "   \n  ")
        #expect(ride.customName == nil)
    }

    @Test func rideAutomaticNameUsesBothStreetAddresses() {
        let ride = TrackedRide()

        #expect(ride.automaticName == nil)

        ride.startAddress = "  123 Tree St, Los Angeles, CA 90001  "
        ride.endAddress = "456 Acorn Ln\nPasadena, CA 91101\nUnited States"

        #expect(ride.automaticName == "123 Tree St to 456 Acorn Ln")
    }

    @Test func placeNameFormatterTruncatesAfterFourteenCharacters() {
        #expect(RideAddressFormatter.placeName(from: "Starbucks") == "Starbucks")
        #expect(
            RideAddressFormatter.placeName(from: "Apple Palo Alto")
                == "Apple Palo Alt..."
        )
        #expect(RideAddressFormatter.placeName(from: "  Peet's  ") == "Peet's")
        #expect(RideAddressFormatter.placeName(from: "  \n ") == nil)
    }

    @Test func streetAddressFormatterRemovesLocality() {
        #expect(
            RideAddressFormatter.street(
                from: "1 Apple Park Way\nCupertino, CA 95014\nUnited States"
            ) == "1 Apple Park Way"
        )
        #expect(
            RideAddressFormatter.street(
                from: "123 Tree St, Los Angeles, CA 90001"
            ) == "123 Tree St"
        )
        #expect(RideAddressFormatter.street(from: "  \n ") == nil)
    }

    @Test func rideAgeUsesOnlyTheLargestTimeDenomination() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(
            RideMetrics.ageDescription(
                since: now.addingTimeInterval(-5),
                relativeTo: now
            ) == "5 seconds ago"
        )
        #expect(
            RideMetrics.ageDescription(
                since: now.addingTimeInterval(-40 * 60),
                relativeTo: now
            ) == "40 minutes ago"
        )
        #expect(
            RideMetrics.ageDescription(
                since: now.addingTimeInterval(-90 * 60),
                relativeTo: now
            ) == "1 hour ago"
        )
    }

    @Test func rideSummaryMetricsUseCompactDurationAndNumericMiles() {
        #expect(
            RideMetrics.duration(270, omittingZeroHours: true) == "04:30"
        )
        #expect(
            RideMetrics.duration(3_870, omittingZeroHours: true) == "01:04:30"
        )
        #expect(RideMetrics.miles(1_609.344) == "1.0")
    }

    @Test func homeActivityUsesARollingSevenDayWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let withinWindow = TrackedRide(
            startedAt: now.addingTimeInterval(-(7 * 24 * 60 * 60) + 1)
        )
        let atWindowStart = TrackedRide(
            startedAt: now.addingTimeInterval(-7 * 24 * 60 * 60)
        )
        let beforeWindow = TrackedRide(
            startedAt: now.addingTimeInterval(-(7 * 24 * 60 * 60) - 1)
        )
        let futureRide = TrackedRide(startedAt: now.addingTimeInterval(1))

        #expect(
            RideMetrics.startedInLastSevenDays(
                withinWindow,
                relativeTo: now
            )
        )
        #expect(
            RideMetrics.startedInLastSevenDays(
                atWindowStart,
                relativeTo: now
            )
        )
        #expect(
            !RideMetrics.startedInLastSevenDays(
                beforeWindow,
                relativeTo: now
            )
        )
        #expect(
            !RideMetrics.startedInLastSevenDays(
                futureRide,
                relativeTo: now
            )
        )
    }

    @Test func routeSpeedUsesTheMedianMovingSegmentAsNormal() {
        #expect(RideRouteSpeed.typicalMovingSpeed([0.2, 8, 10, 30]) == 10)
        #expect(RideRouteSpeed.typicalMovingSpeed([8, 12]) == 10)
        #expect(RideRouteSpeed.typicalMovingSpeed([0, 0.5, 1]) == nil)
    }

    @MainActor
    @Test func routeSpeedClassifiesNormalSlowAndStoppedMotion() {
        #expect(
            RideRouteSpeed.motion(for: 12, normalSpeed: 12)
                == .normalOrFaster
        )
        #expect(
            RideRouteSpeed.motion(for: 16, normalSpeed: 12)
                == .normalOrFaster
        )
        #expect(RideRouteSpeed.motion(for: 6, normalSpeed: 12) == .slower)
        #expect(RideRouteSpeed.motion(for: 1, normalSpeed: 12) == .stopped)
        #expect(RideRouteSpeed.motion(for: 0, normalSpeed: nil) == .stopped)
    }

    @MainActor
    @Test func routeSegmentsDeriveMotionFromSavedPositionsAndTimes() {
        let start = Date(timeIntervalSince1970: 10_000)
        let points = [
            RideRoutePoint(
                latitude: 0,
                longitude: 0,
                horizontalAccuracy: 5,
                recordedAt: start
            ),
            RideRoutePoint(
                latitude: 0,
                longitude: 0,
                horizontalAccuracy: 5,
                recordedAt: start.addingTimeInterval(60)
            ),
            RideRoutePoint(
                latitude: 0,
                longitude: 0.001,
                horizontalAccuracy: 5,
                recordedAt: start.addingTimeInterval(120)
            ),
            RideRoutePoint(
                latitude: 0,
                longitude: 0.003,
                horizontalAccuracy: 5,
                recordedAt: start.addingTimeInterval(180)
            ),
        ]

        #expect(
            RideRouteSpeed.segments(for: points).map(\.motion)
                == [.stopped, .slower, .normalOrFaster]
        )
    }

    @MainActor
    @Test func routeStopsRequireMoreThanFifteenSeconds() {
        let start = Date(timeIntervalSince1970: 10_000)
        let fifteenSecondStop = [
            routePoint(at: start),
            routePoint(at: start.addingTimeInterval(15)),
        ]
        let twentySecondStop = [
            routePoint(at: start),
            routePoint(at: start.addingTimeInterval(10)),
            routePoint(at: start.addingTimeInterval(20)),
        ]

        #expect(RideRouteSpeed.stops(for: fifteenSecondStop).isEmpty)
        #expect(RideRouteSpeed.stops(for: twentySecondStop).count == 1)
    }

    @MainActor
    @Test func routeStopsMergeConsecutiveStationarySegments() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let points = [
            routePoint(latitude: 34, longitude: -118, at: start),
            routePoint(
                latitude: 34.000_01,
                longitude: -118.000_01,
                at: start.addingTimeInterval(10)
            ),
            routePoint(
                latitude: 34.000_02,
                longitude: -118.000_02,
                at: start.addingTimeInterval(20)
            ),
        ]

        let stop = try #require(RideRouteSpeed.stops(for: points).first)

        #expect(stop.startedAt == start)
        #expect(stop.endedAt == start.addingTimeInterval(20))
        #expect(abs(stop.coordinate.latitude - 34.000_01) < 0.000_001)
        #expect(abs(stop.coordinate.longitude + 118.000_01) < 0.000_001)
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

    private func routePoint(
        latitude: Double = 0,
        longitude: Double = 0,
        at date: Date
    ) -> RideRoutePoint {
        RideRoutePoint(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: 5,
            recordedAt: date
        )
    }
}
