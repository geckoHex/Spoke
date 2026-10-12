import AVFoundation
import Foundation

actor RideAudioPlayer {
    private let resourceURL: URL?
    private let audioSession = RideAudioSession.shared
    private var audioPlayer: AVAudioPlayer?
    private var deactivationTask: Task<Void, Never>?
    private var playbackID: UUID?

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    func play() async {
        guard let resourceURL else { return }

        await stopPlayback()

        do {
            let player = try AVAudioPlayer(contentsOf: resourceURL)
            player.prepareToPlay()
            let id = UUID()

            guard await audioSession.activate(for: id) else { return }

            guard player.play() else {
                await audioSession.deactivate(for: id)
                return
            }

            audioPlayer = player
            playbackID = id
            deactivationTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(player.duration))
                } catch {
                    return
                }

                await self?.finishPlayback(id: id)
            }
        } catch {
            await stopPlayback()
        }
    }

    func stop() async {
        await stopPlayback()
    }

    private func finishPlayback(id: UUID) async {
        guard playbackID == id else { return }
        await stopPlayback()
    }

    private func stopPlayback() async {
        deactivationTask?.cancel()
        deactivationTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        let id = playbackID
        playbackID = nil

        if let id {
            await audioSession.deactivate(for: id)
        }
    }
}
