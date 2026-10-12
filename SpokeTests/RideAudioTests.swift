import AVFoundation
import Testing
@testable import Spoke

struct RideAudioTests {
    @Test(arguments: ["ride-start", "ride-end"])
    func rideCueIsBundledAndPlayable(resource: String) throws {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: "mp3"))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 0)
        #expect(player.prepareToPlay())
    }
}
