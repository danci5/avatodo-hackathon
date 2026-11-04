import Foundation
@preconcurrency import AVFoundation

@MainActor final class MicrophoneCapture {
    private var engine: AVAudioEngine?
    private var generation = UUID()
    private var packets: AudioPacketQueue?
    private var receive: (@MainActor (Data, Double) -> Void)?
    private var failed: (@MainActor (AudioFailure) -> Void)?
    private var ownsSession = false
    func start(receive: @escaping @MainActor (Data, Double) -> Void,
               failed: @escaping @MainActor (AudioFailure) -> Void) async throws {
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
        self.receive = receive; self.failed = failed
        let session = AVAudioSession.sharedInstance()
        do {
            #if os(iOS)
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            #else
            try session.setCategory(.playAndRecord, mode: .voiceChat)
            #endif
            try session.setActive(true)
            ownsSession = true
            // Inspect the route before asking AVAudioEngine to initialize RemoteIO.
            // Empty or unavailable inputs must take the typed-message fallback.
            guard session.isInputAvailable, !(session.availableInputs ?? []).isEmpty,
                  session.inputNumberOfChannels > 0, session.sampleRate.isFinite, session.sampleRate > 0 else {
                throw AudioFailure.inputUnavailable
            }
            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw AudioFailure.inputUnavailable
            }
            guard let encoder = RelayPCMEncoder(inputFormat: format) else {
                throw AudioFailure.conversionFailed
            }
            let packets = AudioPacketQueue(); self.packets = packets
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable [weak self] buffer, _ in
                let schedule = packets.encodeAndAppend { encoder.encode(buffer) }
                guard schedule else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    do { try self.deliver(packets.drain(), token: token) }
                    catch is CancellationError { }
                    catch {
                        let callback = self.failed
                        self.stop()
                        callback?(error as? AudioFailure ?? .conversionFailed)
                    }
                }
            }
            self.engine = engine
            engine.prepare()
            try engine.start()
        } catch let error as AudioFailure { stop(); throw error }
        catch { stop(); throw AudioFailure.captureStart(code: (error as NSError).code) }
    }
    /// Stop the producer and synchronously deliver the bounded accepted tail.
    /// Audio-session ownership stays alive until recognition finishes or is cancelled.
    /// Close waits for a conversion already in progress; callbacks entering after
    /// that boundary are discarded and cannot join the next capture.
    func finishCapture() throws {
        let token = generation
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        guard let packets else { throw AudioFailure.inputUnavailable }
        do {
            try deliver(packets.drain(closing: true), token: token)
            guard generation == token else { throw CancellationError() }
            generation = UUID(); self.packets = nil; receive = nil; failed = nil
        } catch {
            if generation == token { stop() }
            throw error
        }
    }
    private func deliver(_ batch: AudioPacketQueue.Batch, token: UUID) throws {
        guard generation == token else { throw CancellationError() }
        if let failure = batch.failure {
            throw failure == .overflow ? AudioFailure.bufferOverflow : AudioFailure.conversionFailed
        }
        for bytes in batch.packets {
            guard generation == token else { throw CancellationError() }
            receive?(bytes, 16_000)
        }
    }
    func releaseSession() {
        guard ownsSession else { return }
        ownsSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stop() {
        generation = UUID()
        packets?.discard(); packets = nil; receive = nil; failed = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        releaseSession()
    }
}

@MainActor final class DeviceVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceID: ObjectIdentifier?
    private var onEnd: (@MainActor () -> Void)?
    private var ownsSession = false
    override init() { super.init(); synthesizer.delegate = self }
    func speak(_ text: String, ended: @escaping @MainActor () -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            ownsSession = true
            let utterance = AVSpeechUtterance(string: String(text.prefix(8000)))
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utteranceID = ObjectIdentifier(utterance); onEnd = ended
            synthesizer.speak(utterance)
        } catch { releaseSession(); throw error }
    }
    func stop() {
        utteranceID = nil; onEnd = nil
        synthesizer.stopSpeaking(at: .immediate)
        releaseSession()
    }
    private func releaseSession() {
        // Nonspeaking Watch state updates call stop(); an idle player must not
        // deactivate the active microphone's shared audio session.
        guard ownsSession else { return }
        ownsSession = false
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
            self.releaseSession()
            callback?()
        }
    }
}

enum AudioFailure: Error, LocalizedError {
    case microphoneDenied, speechDenied, unavailable, incompleteAudio, noWords, simulatorInput
    case inputUnavailable, conversionFailed, bufferOverflow, captureStart(code: Int)
    var errorDescription: String? {
        switch self {
        case .simulatorInput: "Live microphone capture is disabled in this simulator. Type a message or test on a physical device."
        case .microphoneDenied: "Allow microphone access in Settings to talk. You can also type on iPhone."
        case .speechDenied: "Allow speech recognition in iPhone Settings to talk. You can also type."
        case .unavailable: "Speech is unavailable right now. Try again or type on iPhone."
        case .inputUnavailable: "The microphone input is unavailable. Nothing was sent. Try again or type on iPhone."
        case .conversionFailed: "Microphone audio could not be prepared for speech. Nothing was sent. Try again or type on iPhone."
        case .bufferOverflow: "Microphone audio was interrupted while the app was busy. Nothing was sent. Try again or type on iPhone."
        case let .captureStart(code): "Microphone capture could not start (code \(code)). Nothing was sent. Try again or type on iPhone."
        case .incompleteAudio: "The audio connection was interrupted. Nothing was sent to the agent. Try again."
        case .noWords: "I didn’t catch any words. Try again."
        }
    }
}
