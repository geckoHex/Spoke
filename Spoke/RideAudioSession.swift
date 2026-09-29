//
//  RideAudioSession.swift
//  Spoke
//

import AVFoundation
import Foundation

actor RideAudioSession {
    static let shared = RideAudioSession()

    private var activePlaybackIDs: Set<UUID> = []
    private var speakerPlaybackID: UUID?

    func activate(for playbackID: UUID, throughSpeaker: Bool = false) -> Bool {
        guard speakerPlaybackID == nil || speakerPlaybackID == playbackID else { return false }

        if activePlaybackIDs.isEmpty || throughSpeaker {
            do {
                let session = AVAudioSession.sharedInstance()
                if throughSpeaker {
                    try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
                    try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                } else {
                    try session.setCategory(.playback, mode: .default)
                }
                try session.setActive(true)
                if throughSpeaker {
                    try session.overrideOutputAudioPort(.speaker)
                    speakerPlaybackID = playbackID
                }
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

        if speakerPlaybackID == playbackID {
            speakerPlaybackID = nil
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
            if !activePlaybackIDs.isEmpty {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            }
        }

        guard activePlaybackIDs.isEmpty else { return }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func restoreSpeaker(for playbackID: UUID) {
        guard speakerPlaybackID == playbackID else { return }
        let session = AVAudioSession.sharedInstance()
        guard !session.currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker })
        else { return }
        try? session.overrideOutputAudioPort(.speaker)
    }
}
