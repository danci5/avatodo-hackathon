import Foundation
@preconcurrency import AVFoundation

struct RenderedReplyAudio: Sendable { let data: Data; let duration: Double }

/// Produces an ephemeral compressed reply using the same public voice selector
/// as phone playback. The voice pack and Google/Meta credentials never leave iPhone.
@MainActor final class PhoneSpeechRenderer {
    private let synthesizer = AVSpeechSynthesizer()
    private var generation = UUID()
    private var continuation: CheckedContinuation<RenderedReplyAudio, any Error>?
    private var sink: ReplyAudioSink?
    private var watchdog: Task<Void, Never>?

    init() { synthesizer.usesApplicationAudioSession = false }
    func render(_ text: String, preferredID: String?, language: String) async throws -> RenderedReplyAudio {
        cancel()
        guard let voice = DeviceVoice.select(preferredID: preferredID, language: language),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReplyAudioFailure.unavailable }
        let id = UUID(); generation = id
        let sink = try ReplyAudioSink(); self.sink = sink
        let utterance = AVSpeechUtterance(string: String(text.prefix(8000)))
        utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                synthesizer.write(utterance) { [weak self, sink] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else {
                        Task { @MainActor [weak self] in self?.finish(id, result: .failure(ReplyAudioFailure.invalid)) }; return
                    }
                    if let result = sink.receive(pcm) {
                        Task { @MainActor [weak self] in self?.finish(id, result: result) }
                    }
                }
                watchdog = Task { [weak self] in
                    for _ in 0..<120 {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled, let self, generation == id else { return }
                        if sink.stalled { finish(id, result: .failure(ReplyAudioFailure.timedOut)); return }
                    }
                    self?.finish(id, result: .failure(ReplyAudioFailure.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.generation == id else { return }; self?.cancel()
            }
        }
    }
    func cancel() {
        generation = UUID(); watchdog?.cancel(); watchdog = nil
        let continuation = continuation; self.continuation = nil
        sink?.cancel(); sink = nil; synthesizer.stopSpeaking(at: .immediate)
        continuation?.resume(throwing: CancellationError())
    }
    private func finish(_ id: UUID, result: Result<RenderedReplyAudio, any Error>) {
        guard generation == id, let continuation else { return }
        generation = UUID(); self.continuation = nil
        watchdog?.cancel(); watchdog = nil; sink?.cancel(); sink = nil
        synthesizer.stopSpeaking(at: .immediate)
        continuation.resume(with: result)
    }
}

/// AVSpeech callbacks may arrive off the main actor. Writing/closing share one
/// lock; buffers are consumed synchronously and never escape their callback.
private final class ReplyAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let created = ProcessInfo.processInfo.systemUptime
    private var lastBuffer: TimeInterval?
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var rate: Double?
    private var closed = false
    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AvatodoReplyAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        url = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        for old in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            guard old.pathExtension == "m4a", UUID(uuidString: old.deletingPathExtension().lastPathComponent) != nil,
                  let date = try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < Date().addingTimeInterval(-3600) else { continue }
            try? FileManager.default.removeItem(at: old)
        }
    }
    var stalled: Bool {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        return !closed && (lastBuffer.map { now - $0 > 10 } ?? (now - created > 8))
    }
    func receive(_ buffer: AVAudioPCMBuffer) -> Result<RenderedReplyAudio, any Error>? {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return nil }
        do {
            if buffer.frameLength == 0 {
                guard let rate, frames > 0 else { throw ReplyAudioFailure.unavailable }
                file = nil
                let data = try Data(contentsOf: url)
                guard !data.isEmpty, data.count <= ReplyAudioManifest.maximumBytes else { throw ReplyAudioFailure.tooLong }
                closed = true; try? FileManager.default.removeItem(at: url)
                return .success(RenderedReplyAudio(data: data, duration: Double(frames) / rate))
            }
            let format = buffer.format
            guard format.sampleRate.isFinite, format.sampleRate >= 16000, format.sampleRate <= 96000,
                  (1...2).contains(format.channelCount) else { throw ReplyAudioFailure.invalid }
            if file == nil {
                rate = format.sampleRate
                file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
                    AVEncoderBitRateKey: 48000, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue],
                    commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            }
            guard let rate, rate == format.sampleRate,
                  Double(frames + AVAudioFramePosition(buffer.frameLength)) / rate <= 45 else { throw ReplyAudioFailure.tooLong }
            try file?.write(from: buffer); frames += AVAudioFramePosition(buffer.frameLength)
            lastBuffer = ProcessInfo.processInfo.systemUptime
            return nil
        } catch {
            closed = true; file = nil; try? FileManager.default.removeItem(at: url)
            return .failure(error)
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        closed = true; file = nil; try? FileManager.default.removeItem(at: url)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
