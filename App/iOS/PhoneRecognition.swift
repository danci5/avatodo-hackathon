import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation
import AvatodoCore

@MainActor final class PhoneRecognition {
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var generation = UUID()
    private var result = SpeechFinalization()
    private(set) var onDevice = false
    var hasRecognizedWords: Bool { result.hasRecognizedWords }

    func start(partial: @escaping @MainActor (String) -> Void,
               failed: @escaping @MainActor (SpeechRecognitionFailure) -> Void) async throws {
        cancel()
        let token = UUID(); generation = token
        let authorization = await Self.authorization()
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard authorization == .authorized else { throw AudioFailure.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else { throw SpeechRecognitionFailure.unavailable }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        onDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
        self.request = request
        self.result = SpeechFinalization()
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let done = result?.isFinal ?? false
            let issue = error.map { SpeechServiceIssue(domain: ($0 as NSError).domain, code: ($0 as NSError).code) }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.result.receive(text: words, isFinal: done, issue: issue)
                if let failure = self.result.failure { failed(failure); return }
                if let words { partial(words) }
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
        try result.submitAudio(sampleCount: Int(buffer.frameLength))
        request.append(buffer)
    }
    func finish() async throws -> String? {
        let token = generation
        // Cleanup belongs to this turn only; cancellation must not tear down a new one.
        defer { if generation == token { cancel() } }
        guard let request, let recognition else { throw SpeechRecognitionFailure.unavailable }
        guard result.submittedSamples > 0 else { return nil }
        request.endAudio()
        recognition.finish()
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            if result.resolved { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        return try result.finalizedTextOrEmpty()
    }
    func cancel() {
        generation = UUID(); recognition?.cancel(); recognition = nil
        request?.endAudio(); request = nil; recognizer = nil
        result = SpeechFinalization(); onDevice = false
    }
}
