import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

@MainActor final class PhoneRecognition {
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var final = false
    private(set) var text = ""
    private(set) var failure: String?
    private(set) var onDevice = false

    func start(partial: @escaping @MainActor (String) -> Void, failed: @escaping @MainActor () -> Void) async throws {
        cancel()
        let token = UUID(); generation = token
        let authorization = await Self.authorization()
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard authorization == .authorized else { throw AudioFailure.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else { throw AudioFailure.unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        onDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
        self.request = request
        final = false; text = ""; failure = nil
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let done = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let words { self.text = words; partial(words) }
                if done { self.final = true }
                if hasError && !self.final {
                    self.failure = "Speech recognition ended. Try again or type your request."
                    failed()
                }
            }
        }
    }
    /// TCC invokes this legacy callback on a background queue. Create it outside
    /// MainActor so Swift 6 does not infer a main-queue executor requirement.
    private nonisolated static func authorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }
    func append(_ data: Data, sampleRate: Double) throws {
        guard let request, data.count > 0, data.count <= 32_768, data.count % 2 == 0,
              sampleRate == 16_000,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)),
              let channel = buffer.floatChannelData?[0] else { throw AudioFailure.incompleteAudio }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { bytes in
            for index in 0..<Int(buffer.frameLength) {
                let sample = bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
                channel[index] = Float(Int16(littleEndian: sample)) / 32_768
            }
        }
        request.append(buffer)
    }
    func finish() async throws -> String {
        request?.endAudio()
        let token = generation
        for _ in 0..<30 {
            guard generation == token else { throw CancellationError() }
            if final || failure != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard generation == token else { throw CancellationError() }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let complete = final && failure == nil
        cancel()
        // An interrupted recognizer or a timed-out partial must never become a tool request.
        guard complete else { throw AudioFailure.unavailable }
        guard !words.isEmpty else { throw AudioFailure.noWords }
        return words
    }
    func cancel() {
        generation = UUID(); recognition?.cancel(); recognition = nil
        request?.endAudio(); request = nil
    }
}
