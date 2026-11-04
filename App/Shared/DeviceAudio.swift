import Foundation
@preconcurrency import AVFoundation

@MainActor final class MicrophoneCapture {
    private var engine: AVAudioEngine?
    private var generation = UUID()
    func start(receive: @escaping @MainActor (Data, Double) -> Void) async throws {
        stop()
        #if targetEnvironment(simulator)
        // Some Simulator runtimes abort inside their audio service before Swift can catch an error.
        // Keep source/UI testing safe by default; real-device capture is unaffected.
        guard ProcessInfo.processInfo.environment["AVATODO_ENABLE_SIMULATOR_MICROPHONE"] == "1" else {
            throw AudioFailure.simulatorInput
        }
        #endif
        let token = UUID(); generation = token
        let allowed = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard allowed else { throw AudioFailure.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        #else
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        #endif
        try session.setActive(true)
        // Inspect the route before asking AVAudioEngine to initialize RemoteIO.
        // Empty or unavailable inputs must take the typed-message fallback.
        guard session.isInputAvailable, !(session.availableInputs ?? []).isEmpty,
              session.inputNumberOfChannels > 0, session.sampleRate.isFinite, session.sampleRate > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioFailure.unavailable
        }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioFailure.unavailable
        }
        guard let encoder = RelayPCMEncoder(inputFormat: format) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioFailure.unavailable
        }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable [weak self] buffer, _ in
            guard let bytes = encoder.encode(buffer), !bytes.isEmpty else { return }
            let rate = 16_000.0
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                receive(bytes, rate)
            }
        }
        self.engine = engine
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
    }
    func stop() {
        generation = UUID()
        let wasRecording = engine != nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        if wasRecording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

@MainActor final class DeviceVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceID: ObjectIdentifier?
    private var onEnd: (@MainActor () -> Void)?
    override init() { super.init(); synthesizer.delegate = self }
    func speak(_ text: String, ended: @escaping @MainActor () -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        let utterance = AVSpeechUtterance(string: String(text.prefix(8000)))
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utteranceID = ObjectIdentifier(utterance); onEnd = ended
        synthesizer.speak(utterance)
    }
    func stop() {
        utteranceID = nil; onEnd = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }
    nonisolated private func finished(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            let callback = self.onEnd
            self.utteranceID = nil; self.onEnd = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            callback?()
        }
    }
}

enum AudioFailure: Error, LocalizedError {
    case microphoneDenied, speechDenied, unavailable, incompleteAudio, noWords, simulatorInput
    var errorDescription: String? {
        switch self {
        case .simulatorInput: "Live microphone capture is disabled in this simulator. Type a message or test on a physical device."
        case .microphoneDenied: "Allow microphone access in Settings to talk. You can also type on iPhone."
        case .speechDenied: "Allow speech recognition in iPhone Settings to talk. You can also type."
        case .unavailable: "Speech is unavailable right now. Try again or type on iPhone."
        case .incompleteAudio: "The audio connection was interrupted. Nothing was sent to the agent. Try again."
        case .noWords: "I didn’t catch any words. Try again."
        }
    }
}
