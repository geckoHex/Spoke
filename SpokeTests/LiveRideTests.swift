import Foundation
import SwiftData
import Testing
@testable import Spoke

@MainActor
struct LiveRideTests {
    private let now = Date(timeIntervalSince1970: 18_000)

    @Test func newestSpeedReplacesPendingReadings() {
        var policy = LiveRidePolicy()
        policy.didStart(.speedChanged(15))
        policy.submit(.speedChanged(16), at: now.addingTimeInterval(1))
        policy.submit(.speedChanged(18), at: now.addingTimeInterval(2))
        policy.submit(.speedChanged(20), at: now.addingTimeInterval(3))
        #expect(policy.takeNext(at: now.addingTimeInterval(3)) == .speedChanged(20))
        policy.didStart(.speedChanged(20))
        #expect(policy.takeNext(at: now.addingTimeInterval(4)) == .speedChanged(20))
    }

    @Test func returningToOriginalSpeedReplacesPendingChange() {
        var policy = LiveRidePolicy()
        policy.didStart(.speedChanged(15))
        policy.submit(.speedChanged(18), at: now.addingTimeInterval(2))
        policy.submit(.speedChanged(15), at: now.addingTimeInterval(3))
        #expect(policy.takeNext(at: now.addingTimeInterval(3)) == .speedChanged(15))
    }

    @Test func unchangedSpeedIsReadyAfterEveryUtteranceWithoutWaitingForAnotherGPSUpdate() {
        var policy = LiveRidePolicy()
        policy.submit(.speedChanged(15), at: now)
        for offset in [0.0, 1.25, 2.5] {
            let event = policy.takeNext(at: now.addingTimeInterval(offset))
            #expect(event == .speedChanged(15))
            policy.didStart(.speedChanged(15))
        }
        // Repeating telemetry must not extend the underlying observation's freshness.
        #expect(policy.takeNext(at: now.addingTimeInterval(4)) == nil)
        policy.submit(.speedChanged(15), at: now.addingTimeInterval(4))
        #expect(policy.takeNext(at: now.addingTimeInterval(4.25)) == .speedChanged(15))
    }

    @Test func contextWinsAndSpeedImmediatelyFillsTheFollowingGap() {
        var policy = LiveRidePolicy()
        policy.submit(.speedChanged(15), at: now)
        policy.didStart(.speedChanged(15))
        policy.submit(.enteredCity("Los Altos"), at: now.addingTimeInterval(1))
        policy.submit(.speedChanged(16), at: now.addingTimeInterval(1.1))
        #expect(policy.takeNext(at: now.addingTimeInterval(1.25)) == .enteredCity("Los Altos"))
        policy.didStart(.enteredCity("Los Altos"))
        #expect(policy.takeNext(at: now.addingTimeInterval(2.5)) == .speedChanged(16))
        policy.categories.remove(.speed)
        #expect(policy.takeNext(at: now.addingTimeInterval(2.75)) == nil)
    }

    @Test func priorityReplacesPendingButNeverResurrectsStaleContext() {
        var policy = LiveRidePolicy()
        policy.submit(.clockTime(now), at: now)
        policy.submit(.streetChanged("Camellia Way"), at: now.addingTimeInterval(1))
        policy.submit(.speedChanged(18), at: now.addingTimeInterval(2))
        #expect(policy.pending?.event == .streetChanged("Camellia Way"))
        policy.submit(.enteredCity("Los Altos"), at: now.addingTimeInterval(3))
        #expect(policy.pending?.event == .enteredCity("Los Altos"))
        policy.submit(.speedChanged(20), at: now.addingTimeInterval(16))
        #expect(policy.takeNext(at: now.addingTimeInterval(16)) == .speedChanged(20))
    }

    @Test func oldSpeedAndDisabledCategoriesAreDiscarded() {
        var policy = LiveRidePolicy()
        policy.submit(.speedChanged(18), at: now)
        #expect(policy.takeNext(at: now.addingTimeInterval(4)) == nil)
        policy.submit(.streetChanged("Camellia Way"), at: now.addingTimeInterval(4))
        policy.categories.remove(.streets)
        #expect(policy.takeNext(at: now.addingTimeInterval(5)) == nil)
        policy.categories.remove(.speed)
        policy.submit(.speedChanged(20), at: now.addingTimeInterval(5))
        #expect(policy.pending == nil)
    }

    @Test func pendingContextCanBeInvalidatedAndSpokenContextIsDeduplicated() {
        var policy = LiveRidePolicy()
        policy.submit(.streetChanged("Camellia Way"), at: now)
        policy.invalidate(.streets)
        #expect(policy.takeNext(at: now) == nil)
        policy.didStart(.enteredCity("Los Altos"))
        policy.submit(.enteredCity("Los Altos"), at: now.addingTimeInterval(1))
        #expect(policy.pending == nil)
        policy = LiveRidePolicy()
        policy.submit(.speedChanged(15), at: now.addingTimeInterval(2))
        #expect(policy.takeNext(at: now.addingTimeInterval(2)) == .speedChanged(15))
    }

    @Test func prioritiesAndWordingMatchRideTelemetry() {
        let events: [LiveRideEvent] = [
            .speedChanged(18), .clockTime(now), .rideDuration(300),
            .distanceMilestone(3), .streetChanged("Camellia Way"), .enteredCity("Los Altos")
        ]
        #expect(events.map(\.category.rawValue) == [20, 40, 50, 70, 80, 100])
        #expect(events[0].text == "Speed 18.")
        #expect(LiveRideEvent.distanceMilestone(1).text == "One mile.")
        #expect(LiveRideEvent.distanceMilestone(23).text == "Twenty-three miles.")
        #expect(LiveRideEvent.rideDuration(900).text == "Riding for 15 minutes.")
        #expect(LiveRideEvent.rideDuration(3_600).text == "Riding for one hour.")
        #expect(LiveRideEvent.rideDuration(4_200).text == "Riding for one hour and 10 minutes.")
    }

    @Test func progressProducesBoundariesOnceAndSkipsCatchUp() {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10, minute: 12))!
        var progress = LiveRideProgress(distance: 0, duration: 0, now: start)
        let clock = start.addingTimeInterval(180)
        #expect(progress.events(distance: 1_610, duration: 300, now: clock) == [
            .distanceMilestone(1), .rideDuration(300), .clockTime(clock)
        ])
        #expect(progress.events(distance: 1_611, duration: 301, now: clock.addingTimeInterval(1)).isEmpty)
        #expect(progress.events(distance: 1_611, duration: 920, now: clock.addingTimeInterval(200)).isEmpty)
        // Restoring a ride at an existing milestone must not replay its history.
        progress = LiveRideProgress(distance: 8_100, duration: 1_200, now: clock)
        #expect(progress.events(distance: 8_100, duration: 1_200, now: clock).isEmpty)
    }

    @Test func streetConfirmationRejectsSingleOutliersAndRapidBounce() {
        var state = LiveRidePlaceConfirmation()
        #expect(state.observe("A Street", at: now, isCity: false) == nil)
        #expect(state.observe("A Street", at: now.addingTimeInterval(6), isCity: false) == nil)
        #expect(state.confirmed == "A Street")
        #expect(state.observe("B Street", at: now.addingTimeInterval(12), isCity: false) == nil)
        #expect(state.observe("A Street", at: now.addingTimeInterval(18), isCity: false) == nil)
        #expect(state.observe("B Street", at: now.addingTimeInterval(24), isCity: false) == nil)
        #expect(state.observe("B Street", at: now.addingTimeInterval(30), isCity: false) == "B Street")
        #expect(state.observe("A Street", at: now.addingTimeInterval(36), isCity: false) == nil)
        #expect(state.observe("A Street", at: now.addingTimeInterval(42), isCity: false) == nil)
    }

    @Test func citiesRequireThreeConfirmationsAndMissingResultsResetCandidates() {
        var state = LiveRidePlaceConfirmation()
        for offset in [0.0, 6, 12] { _ = state.observe("Los Altos", at: now.addingTimeInterval(offset), isCity: true) }
        #expect(state.confirmed == "Los Altos")
        for offset in [18.0, 24] { #expect(state.observe("Sunnyvale", at: now.addingTimeInterval(offset), isCity: true) == nil) }
        #expect(state.observe(nil, at: now.addingTimeInterval(30), isCity: true) == nil)
        for offset in [36.0, 42] { #expect(state.observe("Sunnyvale", at: now.addingTimeInterval(offset), isCity: true) == nil) }
        #expect(state.observe("Sunnyvale", at: now.addingTimeInterval(48), isCity: true) == "Sunnyvale")
    }

    @Test func narrationStreetOmitsHouseNumbersAndRejectsCityOnlyResults() {
        #expect(RideAddressFormatter.narrationStreet(from: "123 Camellia Way, Los Altos", city: "Los Altos") == "Camellia Way")
        #expect(RideAddressFormatter.narrationStreet(from: "12–14 El Monte Avenue", city: "Los Altos") == "El Monte Avenue")
        #expect(RideAddressFormatter.narrationStreet(from: "Los Altos", city: "Los Altos") == nil)
        #expect(RideAddressFormatter.narrationStreet(from: "94022", city: "Los Altos") == nil)
    }

    @Test func settingsDefaultOffAndEveryPreferencePersists() throws {
        let container = try ModelContainer(for: AppSettings.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = AppSettings()
        #expect(!settings.liveRideEnabled)
        #expect(settings.liveRideVoiceIdentifier.isEmpty)
        #expect(LiveRideConfiguration(settings: settings).categories.count == 6)
        context.insert(settings)
        settings.liveRideEnabled = true
        settings.liveRideVoiceIdentifier = "selected.voice"
        settings.liveRideSpeedEnabled = false
        settings.liveRideStreetsEnabled = false
        settings.liveRideCitiesEnabled = false
        settings.liveRideDistanceEnabled = false
        settings.liveRideClockTimeEnabled = false
        settings.liveRideDurationEnabled = false
        try context.save()
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
        let configuration = LiveRideConfiguration(settings: saved)
        #expect(configuration.enabled)
        #expect(configuration.voiceIdentifier == "selected.voice")
        #expect(configuration.categories.isEmpty)
    }
}
