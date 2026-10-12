import AVFoundation
import Testing
@testable import Spoke

struct RideAudioTests {
    @Test(arguments: ["overspeed-alert", "ride-start", "ride-end"])
    func rideCueIsBundledAndPlayable(resource: String) throws {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: "mp3", subdirectory: "sounds"))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 0)
        #expect(player.prepareToPlay())
    }
}
