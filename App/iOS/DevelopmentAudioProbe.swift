#if DEBUG && targetEnvironment(simulator)
import Foundation
@preconcurrency import AVFoundation

@MainActor enum DevelopmentAudioProbe {
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.environment["AVATODO_REPLY_AUDIO_PROBE"] == "1" else { return }
        unsetenv("AVATODO_REPLY_AUDIO_PROBE")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReplyAudioProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report: [String: Any] = [:]
        let renderer = PhoneSpeechRenderer()
        do {
            let selected = DeviceVoice.installedVoiceOptions().first { !$0.isNovelty }
            let language = selected?.language ?? DeviceVoice.defaultLanguage
            for index in 1...2 {
                let clip = try await renderer.render("Hello! Your companion is ready.", preferredID: selected?.id, language: language)
                let url = folder.appendingPathComponent("reply-\(index).m4a")
                try clip.data.write(to: url)
                let file = try AVAudioFile(forReading: url)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                guard clip.data.count > 1000, clip.data.count < ReplyAudioManifest.maximumBytes,
                      duration > 0, abs(duration - clip.duration) < 1 else { throw ReplyAudioFailure.invalid }
                report["render_\(index)"] = ["bytes": clip.data.count, "duration": duration,
                    "voice": selected?.id ?? "automatic", "quality": selected?.quality.rawValue ?? 1]
            }
            let cancelled = Task { try await renderer.render("This cancelled reply must never be delivered.", preferredID: selected?.id, language: language) }
            cancelled.cancel()
            do { _ = try await cancelled.value; throw ReplyAudioFailure.invalid }
            catch is CancellationError { report["cancelled_render"] = true }
            report["passed"] = true
        } catch {
            renderer.cancel(); report["passed"] = false
            report["failure"] = String(describing: type(of: error))
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("results.json"), options: .atomic)
        }
    }
}
#endif
