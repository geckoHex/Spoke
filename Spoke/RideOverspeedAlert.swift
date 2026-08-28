//
//  RideOverspeedAlert.swift
//  Spoke
//

import AVFoundation
import Foundation

actor RideOverspeedAlertController {
    private let thresholdInMilesPerHour = 25
    private let sustainedOverspeedCooldown: Duration = .seconds(5)
    private let reentryCooldown: TimeInterval = 2

    private let player: RideOverspeedAlertPlayer
    private var currentSpeedInMilesPerHour = 0
    private var lastAlertDate: Date?
    private var alertCycleTask: Task<Void, Never>?

    init(player: RideOverspeedAlertPlayer) {
        self.player = player
    }

    func update(speedInMilesPerHour: Int) {
        let wasAboveThreshold = currentSpeedInMilesPerHour > thresholdInMilesPerHour
        currentSpeedInMilesPerHour = speedInMilesPerHour

        guard speedInMilesPerHour > thresholdInMilesPerHour else {
            alertCycleTask?.cancel()
            alertCycleTask = nil
            return
        }

        guard !wasAboveThreshold else { return }

        let initialDelay = if let lastAlertDate {
            max(reentryCooldown - Date().timeIntervalSince(lastAlertDate), 0.0)
        } else {
            0.0
        }

        alertCycleTask?.cancel()
        alertCycleTask = Task { [weak self] in
            if initialDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(initialDelay))
                } catch {
                    return
                }
            }

            await self?.runAlertCycle()
        }
    }

    func stop() async {
        currentSpeedInMilesPerHour = 0
        lastAlertDate = nil
        alertCycleTask?.cancel()
        alertCycleTask = nil
        await player.stop()
    }

    private func runAlertCycle() async {
        while !Task.isCancelled,
              currentSpeedInMilesPerHour > thresholdInMilesPerHour {
            lastAlertDate = Date()
            await player.play()

            do {
                try await Task.sleep(for: sustainedOverspeedCooldown)
            } catch {
                return
            }
        }
    }
}

actor RideOverspeedAlertPlayer {
    private let resourceURL: URL?
    private var audioPlayer: AVAudioPlayer?
    private var deactivationTask: Task<Void, Never>?
    private var playbackID: UUID?

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    func play() {
        guard let resourceURL else { return }

        stopPlayback(deactivateSession: true)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let player = try AVAudioPlayer(contentsOf: resourceURL)
            player.prepareToPlay()

            guard player.play() else {
                deactivateAudioSession()
                return
            }

            let id = UUID()
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
            stopPlayback(deactivateSession: true)
        }
    }

    func stop() {
        stopPlayback(deactivateSession: true)
    }

    private func finishPlayback(id: UUID) {
        guard playbackID == id else { return }
        stopPlayback(deactivateSession: true)
    }

    private func stopPlayback(deactivateSession: Bool) {
        deactivationTask?.cancel()
        deactivationTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playbackID = nil

        if deactivateSession {
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
