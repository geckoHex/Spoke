//
//  SpokeTests.swift
//  SpokeTests
//
//  Created by Beck Orion on 8/27/26.
//

import CoreLocation
import Foundation
import MapKit
import SwiftData
import Testing
@testable import Spoke

struct SpokeTests {
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

    @Test func mapHeadingWaitsForThreeReliableConsistentSamples() async {
        let processor = RideSpeedProcessor()
        let now = Date(timeIntervalSince1970: 10_000)

        let first = await processor.process(
            [mapSample(course: 88, timestamp: now)],
            now: now
        )
        let second = await processor.process(
            [mapSample(course: 91, timestamp: now.addingTimeInterval(1))],
            now: now.addingTimeInterval(1)
        )
        let third = await processor.process(
            [mapSample(course: 89, timestamp: now.addingTimeInterval(2))],
            now: now.addingTimeInterval(2)
        )

        #expect(first.mapHeading == nil)
        #expect(second.mapHeading == nil)
        #expect(abs((third.mapHeading ?? 0) - 89.333) < 0.01)
    }

    @Test func mapHeadingRejectsSlowOrInaccurateMovement() async {
        let processor = RideSpeedProcessor()
        let now = Date(timeIntervalSince1970: 10_000)

        for offset in 0..<4 {
            let update = await processor.process(
                [
                    mapSample(
                        speed: offset.isMultiple(of: 2) ? 2 : 5,
                        course: 180,
                        courseAccuracy: offset.isMultiple(of: 2) ? 5 : 40,
                        timestamp: now.addingTimeInterval(Double(offset))
                    )
                ],
                now: now.addingTimeInterval(Double(offset))
            )

            #expect(update.mapHeading == nil)
        }
    }

    @Test func mapHeadingRequiresAConfirmedTurnAndIgnoresAnOutlier() async {
        var filter = RideMapHeadingFilter()
        let now = Date(timeIntervalSince1970: 10_000)

        _ = filter.update(with: mapSample(course: 90, timestamp: now))
        _ = filter.update(
            with: mapSample(course: 92, timestamp: now.addingTimeInterval(1))
        )
        let initialHeading = filter.update(
            with: mapSample(course: 91, timestamp: now.addingTimeInterval(2))
        )
        let outlierHeading = filter.update(
            with: mapSample(course: 220, timestamp: now.addingTimeInterval(3))
        )
        let pendingTurnHeading = filter.update(
            with: mapSample(course: 178, timestamp: now.addingTimeInterval(4))
        )
        let confirmedTurnHeading = filter.update(
            with: mapSample(course: 182, timestamp: now.addingTimeInterval(5))
        )

        #expect(abs((initialHeading ?? 0) - 91) < 0.01)
        #expect(outlierHeading == initialHeading)
        #expect(pendingTurnHeading == initialHeading)
        #expect(abs((confirmedTurnHeading ?? 0) - 180) < 0.01)
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
            windSpeed: "12 mph",
            windDirection: "NW",
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

    @MainActor
    @Test func completedRideCanBeDiscardedFromPersistence() throws {
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

        let start = Date(timeIntervalSince1970: 1_000)
        let ride = try #require(controller.startRide(at: start))
        _ = controller.endRide(at: start.addingTimeInterval(60))

        #expect(controller.discardRide(ride))
        #expect(try container.mainContext.fetch(FetchDescriptor<TrackedRide>()).isEmpty)
    }

    @MainActor
    @Test func activeRideCannotBeDiscarded() throws {
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
        let ride = try #require(controller.startRide())

        #expect(!controller.discardRide(ride))
        #expect(try container.mainContext.fetch(FetchDescriptor<TrackedRide>()).count == 1)
    }

    @Test func rideRenameTrimsWhitespaceAndCanBeCleared() {
        let ride = TrackedRide()

        ride.rename(to: "  Morning Loop  ")
        #expect(ride.customName == "Morning Loop")

        ride.rename(to: "   \n  ")
        #expect(ride.customName == nil)
    }

    @Test func rideNotePreservesTypedContentAndCanBeCleared() {
        let ride = TrackedRide()

        ride.updateNote(to: "  Strong headwind on the return  ")
        #expect(ride.note == "  Strong headwind on the return  ")

        ride.updateNote(to: "")
        #expect(ride.note == nil)
    }

    @Test func rideAutomaticNameUsesBothEndpointNames() {
        let ride = TrackedRide()

        #expect(ride.automaticName == nil)

        ride.startAddress = "Target"
        ride.endAddress = "Walmart"

        #expect(ride.automaticName == "Target → Walmart")
    }

    @MainActor
    @Test func endpointResolverChoosesTheNearestMapKitPointOfInterest() {
        let endpoint = CLLocation(latitude: 34, longitude: -118)
        let target = MKMapItem(
            location: CLLocation(latitude: 34.000_1, longitude: -118),
            address: nil
        )
        target.name = "Target"
        target.pointOfInterestCategory = .store

        let walmart = MKMapItem(
            location: CLLocation(latitude: 34.000_5, longitude: -118),
            address: nil
        )
        walmart.name = "Walmart"
        walmart.pointOfInterestCategory = .store

        #expect(
            RideAddressResolver.nearestPointOfInterestName(
                to: endpoint,
                among: [walmart, target],
                maximumDistance: 100
            ) == "Target"
        )
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
        #expect(RideMetrics.speedInMilesPerHour(12.345) == "12.3 mph")
    }

    @Test func unpaddedDurationOnlyPadsSeconds() {
        #expect(RideMetrics.unpaddedDuration(243) == "4:03")
        #expect(RideMetrics.unpaddedDuration(3_843) == "1:4:03")
        #expect(RideMetrics.unpaddedDuration(3_605) == "1:0:05")
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
    @Test func movingMetricsExcludeStoppedSegments() {
        let start = Date(timeIntervalSince1970: 10_000)
        let points = [
            routePoint(at: start),
            routePoint(at: start.addingTimeInterval(60)),
            routePoint(
                latitude: 0,
                longitude: 0.001,
                at: start.addingTimeInterval(120)
            ),
            routePoint(
                latitude: 0,
                longitude: 0.003,
                at: start.addingTimeInterval(180)
            ),
        ]

        let metrics = RideRouteSpeed.movingMetrics(for: points)
        let expectedDistance = CLLocation(
            latitude: 0,
            longitude: 0
        ).distance(
            from: CLLocation(latitude: 0, longitude: 0.003)
        )

        #expect(metrics.duration == 120)
        #expect(abs(metrics.distanceInMeters - expectedDistance) < 0.001)
        #expect(
            abs(
                metrics.averageSpeedInMilesPerHour
                    - expectedDistance / 120 * 2.236_936_292_1
            ) < 0.001
        )
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
        #expect(stop.durationDescription == "20 secs")
        #expect(abs(stop.coordinate.latitude - 34.000_01) < 0.000_001)
        #expect(abs(stop.coordinate.longitude + 118.000_01) < 0.000_001)
    }

    @Test func routeStopDurationDescriptionUsesConciseUnits() {
        let start = Date(timeIntervalSince1970: 10_000)
        let coordinate = CLLocationCoordinate2D(latitude: 34, longitude: -118)

        let oneMinuteStop = RideRouteStop(
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            coordinate: coordinate
        )
        let twoMinuteStop = RideRouteStop(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            coordinate: coordinate
        )

        #expect(oneMinuteStop.durationDescription == "1 min")
        #expect(twoMinuteStop.durationDescription == "2 mins")
    }

    @MainActor
    @Test func rideReplayPreservesRecordedTimingWithinTenSeconds() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let route = RideReplayRoute(
            points: [
                routePoint(latitude: 0, longitude: 0, at: start),
                routePoint(
                    latitude: 0,
                    longitude: 0.001,
                    at: start.addingTimeInterval(1)
                ),
                routePoint(
                    latitude: 0,
                    longitude: 0.002,
                    at: start.addingTimeInterval(4)
                ),
            ]
        )

        let quarterCoordinate = try #require(route.coordinate(at: 0.25))
        let fiveEighthsCoordinate = try #require(route.coordinate(at: 0.625))

        #expect(RideReplayRoute.playbackDuration == 10)
        #expect(abs(quarterCoordinate.longitude - 0.001) < 0.000_001)
        #expect(abs(fiveEighthsCoordinate.longitude - 0.0015) < 0.000_001)
    }

    @Test func rideReplayDirectionRequiresConsecutiveHorizontalTravel() {
        let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 40, longitude: -120))
        let pointsPerMeter = 1 / MKMetersPerMapPointAtLatitude(40)
        func coordinate(x: Double, y: Double = 0) -> CLLocationCoordinate2D {
            MKMapPoint(
                x: origin.x + x * pointsPerMeter,
                y: origin.y + y * pointsPerMeter
            ).coordinate
        }

        var direction = RideReplayDirection()
        direction.update(from: coordinate(x: 0), to: coordinate(x: -0.7))
        direction.update(from: coordinate(x: -0.7), to: coordinate(x: -1.4))
        #expect(!direction.isFacingLeft)
        direction.update(from: coordinate(x: -1.4), to: coordinate(x: -1.6))
        #expect(direction.isFacingLeft)

        direction.update(from: coordinate(x: -1.6), to: coordinate(x: -0.2))
        #expect(direction.isFacingLeft)
        direction.update(from: coordinate(x: -0.2), to: coordinate(x: 0))
        #expect(!direction.isFacingLeft)

        // A reversal clears a partial turn instead of combining separate attempts.
        direction.update(from: coordinate(x: 0), to: coordinate(x: -1))
        direction.update(from: coordinate(x: -1), to: coordinate(x: 0))
        direction.update(from: coordinate(x: 0), to: coordinate(x: -1))
        #expect(!direction.isFacingLeft)

        // Vertical travel clears the partial turn, and does not count toward 1.5 m.
        direction.update(from: coordinate(x: -1), to: coordinate(x: -1, y: 10))
        direction.update(from: coordinate(x: -1, y: 10), to: coordinate(x: -2, y: 20))
        #expect(!direction.isFacingLeft)

        // Repeated horizontal jitter while moving vertically never accumulates.
        for step in 0..<20 {
            let y = 20 + Double(step) * 20
            direction.update(from: coordinate(x: -2, y: y), to: coordinate(x: -1.8, y: y + 10))
            direction.update(from: coordinate(x: -1.8, y: y + 10), to: coordinate(x: -2, y: y + 20))
            #expect(!direction.isFacingLeft)
        }
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

    private func mapSample(
        speed: CLLocationSpeed = 5,
        course: CLLocationDirection,
        courseAccuracy: CLLocationDirectionAccuracy = 5,
        timestamp: Date
    ) -> RideLocationSample {
        RideLocationSample(
            latitude: 34,
            longitude: -118,
            horizontalAccuracy: 5,
            speed: speed,
            speedAccuracy: 0.5,
            course: course,
            courseAccuracy: courseAccuracy,
            timestamp: timestamp
        )
    }
}
