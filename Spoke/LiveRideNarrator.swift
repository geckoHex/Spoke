import AVFoundation
import Foundation
import OSLog

@MainActor
final class LiveRideNarrator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = RideAudioSession.shared
    private var policy = LiveRidePolicy()
    private var configuration = LiveRideConfiguration()
    private var isActive = false
    private var isInterrupted = false
    private var generation = UUID()
    private var current: (utterance: AVSpeechUtterance, playbackID: UUID)?
    private var schedulingTask: Task<Void, Never>?

    static var availableVoices: [AVSpeechSynthesisVoice] {
        // Narration is English; preserve each installed voice's stable identifier.
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") }
            .sorted { ($0.name, $0.language, $0.identifier) < ($1.name, $1.language, $1.identifier) }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
    }

    func configure(_ configuration: LiveRideConfiguration) {
        self.configuration = configuration
        policy.categories = configuration.categories
        if !configuration.enabled { reset(active: false) }
        else { tick() }
    }

    func reset(active: Bool) {
        generation = UUID()
        schedulingTask?.cancel()
        schedulingTask = nil
        policy = LiveRidePolicy()
        policy.categories = configuration.categories
        isActive = active && configuration.enabled
        // Lifecycle changes discard pending work. An utterance already audible finishes normally.
        LiveRidePolicy.logger.debug("RESET: active=\(self.isActive)")
    }

    func submit(_ event: LiveRideEvent, at date: Date = .now) {
        guard isActive, configuration.enabled, !isInterrupted else { return }
        policy.submit(event, at: date)
        schedule()
    }

    func invalidate(_ category: LiveRideEvent.Category) {
        policy.invalidate(category)
    }

    func tick() {
        guard isActive, configuration.enabled, !isInterrupted else { return }
        policy.refresh(at: .now)
        schedule()
    }

    private func schedule() {
        guard isActive, !isInterrupted, current == nil,
              schedulingTask == nil, policy.pending != nil else { return }
        let generation = generation
        schedulingTask = Task { [weak self] in
            // A 250 ms gap lets fresh context win while keeping narration continuous.
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard let self, self.generation == generation else { return }
            self.policy.refresh(at: .now)
            guard self.policy.pending != nil else {
                self.schedulingTask = nil
                return
            }
            let playbackID = UUID()
            let activated = await self.audioSession.activateSpokenAlert(for: playbackID)
            guard self.generation == generation, !Task.isCancelled else {
                if activated { await self.audioSession.deactivate(for: playbackID) }
                return
            }
            self.schedulingTask = nil
            guard activated else {
                LiveRidePolicy.logger.debug("PENDING: AUDIO SESSION BUSY")
                return
            }
            guard self.isActive, !self.isInterrupted, self.current == nil,
                  let event = self.policy.takeNext(at: .now) else {
                await self.audioSession.deactivate(for: playbackID)
                return
            }
            let utterance = AVSpeechUtterance(string: event.text)
            utterance.voice = AVSpeechSynthesisVoice(identifier: self.configuration.voiceIdentifier)
                ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            self.current = (utterance, playbackID)
            self.policy.didStart(event)
            // This is the ONLY speak call. AVSpeechSynthesizer never receives a second utterance.
            self.synthesizer.speak(utterance)
        }
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        guard let current, current.utterance === utterance else { return }
        // Keep the slot occupied until the shared audio session is released.
        Task {
            await audioSession.deactivate(for: current.playbackID)
            guard self.current?.utterance === utterance else { return }
            self.current = nil
            tick()
        }
    }

    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        Task { @MainActor [weak self] in
            self?.handleInterruption(value)
        }
    }

    private func handleInterruption(_ value: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        if type == .began {
            generation = UUID()
            isInterrupted = true
            schedulingTask?.cancel()
            schedulingTask = nil
            policy = LiveRidePolicy()
            policy.categories = configuration.categories
            // iOS has already interrupted playback (e.g. a call). Never resume old telemetry.
            if let current {
                synthesizer.stopSpeaking(at: .immediate)
                finished(current.utterance)
            }
        } else {
            isInterrupted = false
            tick()
        }
    }
}

extension LiveRideNarrator: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(utterance)
    }
}
