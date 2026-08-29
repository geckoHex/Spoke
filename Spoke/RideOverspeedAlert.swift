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
