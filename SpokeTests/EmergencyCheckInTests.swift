import Foundation
import SwiftData
import Testing
@testable import Spoke

struct EmergencyCheckInTests {
    @Test func requiresObservedStopAndMoreThanSelectedTimeout() {
        let now = Date(timeIntervalSince1970: 10_000)
        var state = RideEmergencyCheckInState()
        state.evaluate(at: now.addingTimeInterval(1_000), timeoutMinutes: 3)
        #expect(!state.isPresented)
        state.observe(speedInMilesPerHour: 0, at: now)
        state.observe(speedInMilesPerHour: 0, at: now.addingTimeInterval(60))
        state.evaluate(at: now.addingTimeInterval(180), timeoutMinutes: 3)
        #expect(!state.isPresented)
        state.evaluate(at: now.addingTimeInterval(181), timeoutMinutes: 3)
        #expect(state.isPresented)
    }

    @Test func movingResetsTimerAndOkayRestartsItWithoutAutoDismissal() {
        let now = Date(timeIntervalSince1970: 10_000)
        var state = RideEmergencyCheckInState()
        state.observe(speedInMilesPerHour: 0, at: now)
        state.observe(speedInMilesPerHour: 10, at: now.addingTimeInterval(59))
        state.evaluate(at: now.addingTimeInterval(61), timeoutMinutes: 1)
        #expect(!state.isPresented)
        state.observe(speedInMilesPerHour: 0, at: now.addingTimeInterval(70))
        state.evaluate(at: now.addingTimeInterval(131), timeoutMinutes: 1)
        #expect(state.isPresented)
        state.dismiss(at: now.addingTimeInterval(140))
        state.evaluate(at: now.addingTimeInterval(200), timeoutMinutes: 1)
        #expect(!state.isPresented)
        state.evaluate(at: now.addingTimeInterval(201), timeoutMinutes: 1)
        #expect(state.isPresented)
        state.observe(speedInMilesPerHour: 10, at: now.addingTimeInterval(202))
        #expect(state.isPresented)
        state.dismiss(at: now.addingTimeInterval(203))
        state.evaluate(at: now.addingTimeInterval(1_000), timeoutMinutes: 1)
        #expect(!state.isPresented)
    }

    @Test func timeoutSupportsEverySettingsChoice() {
        let now = Date(timeIntervalSince1970: 10_000)
        for minutes in 1...10 {
            var state = RideEmergencyCheckInState()
            state.observe(speedInMilesPerHour: 0, at: now)
            state.evaluate(at: now.addingTimeInterval(Double(minutes * 60)), timeoutMinutes: minutes)
            #expect(!state.isPresented)
            state.evaluate(at: now.addingTimeInterval(Double(minutes * 60 + 1)), timeoutMinutes: minutes)
            #expect(state.isPresented)
        }
    }

    @MainActor
    @Test func timeoutDefaultsToThreeMinutesAndPersists() throws {
        let container = try ModelContainer(
            for: AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let settings = AppSettings()
        #expect(settings.emergencyCheckInMinutes == 3)
        context.insert(settings)
        settings.emergencyCheckInMinutes = 10
        try context.save()
        let saved = try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first
        #expect(saved?.emergencyCheckInMinutes == 10)
        #expect(AppSettings(emergencyCheckInMinutes: 0).emergencyCheckInMinutes == 1)
        #expect(AppSettings(emergencyCheckInMinutes: 11).emergencyCheckInMinutes == 10)
        #expect(Bundle.main.url(forResource: "possible-emergency", withExtension: "mp3") != nil)
    }
}
