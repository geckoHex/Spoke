//
//  RideOverspeedAlert.swift
//  Spoke
//

import Foundation

actor RideOverspeedAlertController {
    private let thresholdInMilesPerHour = 25
    private let sustainedOverspeedCooldown: Duration = .seconds(5)
    private let reentryCooldown: TimeInterval = 2

    private let player: RideAudioPlayer
    private var currentSpeedInMilesPerHour = 0
    private var lastAlertDate: Date?
    private var alertCycleTask: Task<Void, Never>?

    init(player: RideAudioPlayer) {
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
