import AVFoundation
import UIKit
import OSLog

@MainActor
final class RideEmergencyAlerts {
    private let audioSession = RideAudioSession.shared
    private var playbackID: UUID?
    private let logger = Logger(subsystem: "Spoke", category: "EmergencyCheckIn")
    private var audioPlayer: AVAudioPlayer?
    private var isRunning = false
    private var isFlashing = false
    private var torch: AVCaptureDevice?

    func runAudio() async {
        let id = UUID()
        playbackID = id
        isRunning = true
        var player: AVAudioPlayer?
        do {
            if let url = Bundle.main.url(forResource: "possible-emergency", withExtension: "mp3") {
                let alarm = try AVAudioPlayer(contentsOf: url)
                alarm.volume = 1.0
                alarm.prepareToPlay()
                player = alarm
                audioPlayer = alarm
                while isRunning && !Task.isCancelled {
                    if await audioSession.activate(for: id, throughSpeaker: true),
                       isRunning, !Task.isCancelled {
                        alarm.currentTime = 0
                        if alarm.play() {
                            while alarm.isPlaying && isRunning && !Task.isCancelled {
                                try await Task.sleep(for: .milliseconds(50))
                            }
                        }
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } else {
                logger.error("Missing possible-emergency.mp3")
            }
        } catch is CancellationError {
            // Dismissal or backgrounding cancels playback immediately.
        } catch {
            logger.error("Check-in audio failed: \(error.localizedDescription)")
        }
        player?.stop()
        if playbackID == id {
            audioPlayer = nil
            playbackID = nil
        }
        await audioSession.deactivate(for: id)
    }

    func runPhysicalAlerts() async {
        isFlashing = true
        torch = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        let haptics = UIImpactFeedbackGenerator(style: .heavy)
        do {
            while isFlashing && !Task.isCancelled {
                haptics.prepare()
                haptics.impactOccurred(intensity: 1.0)
                setTorch(on: true)
                try await Task.sleep(for: .milliseconds(200))
                setTorch(on: false)
                try await Task.sleep(for: .milliseconds(200))
            }
        } catch {
            // The view cancels this loop when it leaves the screen.
        }
        setTorch(on: false)
    }

    func stop() {
        isRunning = false
        isFlashing = false
        audioPlayer?.stop()
        setTorch(on: false)
    }

    func restoreSpeaker() async {
        if let playbackID { await audioSession.restoreSpeaker(for: playbackID) }
    }

    private func setTorch(on: Bool) {
        guard let torch, torch.hasTorch, torch.isTorchModeSupported(on ? .on : .off),
              !on || torch.isTorchAvailable else { return }
        do {
            try torch.lockForConfiguration()
            defer { torch.unlockForConfiguration() }
            if on {
                try torch.setTorchModeOn(level: 1.0)
            } else {
                torch.torchMode = .off
            }
        } catch {
            logger.error("Check-in torch failed: \(error.localizedDescription)")
        }
    }
}
