import AVFoundation
import SwiftData
import Testing
@testable import Spoke

struct RideAudioTests {
    @MainActor
    @Test func soundEffectsDefaultOnAndPersistChanges() throws {
        let container = try ModelContainer(
            for: AppSettings.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let settings = AppSettings()
        #expect(settings.soundEffectsEnabled)
        container.mainContext.insert(settings)
        settings.soundEffectsEnabled = false
        try container.mainContext.save()

        let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
        #expect(!reloaded.soundEffectsEnabled)
    }

    @Test(arguments: ["overspeed-alert", "ride-start", "ride-end"])
    func rideCueIsBundledAndPlayable(resource: String) throws {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: "mp3", subdirectory: "sounds"))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 0)
        #expect(player.prepareToPlay())
    }
}
