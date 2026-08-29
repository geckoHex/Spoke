//
//  RideSpeedAnnouncer.swift
//  Spoke
//

import AVFoundation
import Foundation

actor RideSpeedAnnouncer {
    static let supportedSpeeds = 1...45

    private let bundle: Bundle
    private let audioSession = RideAudioSession.shared
    private var audioPlayer: AVAudioPlayer?
    private var deactivationTask: Task<Void, Never>?
    private var playbackID: UUID?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    static func resourceName(for speedInMilesPerHour: Int) -> String? {
        guard supportedSpeeds.contains(speedInMilesPerHour) else { return nil }
        return String(speedInMilesPerHour)
    }

    func play(speedInMilesPerHour: Int) async {
        guard let resourceName = Self.resourceName(for: speedInMilesPerHour),
              let resourceURL = bundle.url(
                  forResource: resourceName,
                  withExtension: "mp3",
                  subdirectory: "mph"
              ) ?? bundle.url(forResource: resourceName, withExtension: "mp3")
        else {
            await stopPlayback()
            return
        }

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
