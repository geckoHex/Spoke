//
//  RideAudioSession.swift
//  Spoke
//

import AVFoundation
import Foundation

actor RideAudioSession {
    static let shared = RideAudioSession()

    private var activePlaybackIDs: Set<UUID> = []

    func activate(for playbackID: UUID) -> Bool {
        if activePlaybackIDs.isEmpty {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                if activePlaybackIDs.isEmpty {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
                return false
            }
        }

        activePlaybackIDs.insert(playbackID)
        return true
    }

    func deactivate(for playbackID: UUID) {
        guard activePlaybackIDs.remove(playbackID) != nil else { return }

        guard activePlaybackIDs.isEmpty else { return }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
