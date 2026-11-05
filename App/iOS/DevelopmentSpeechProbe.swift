#if DEBUG && targetEnvironment(simulator)
import Foundation
@preconcurrency import AVFoundation

/// Fixture audio only. Exercises real Apple recognition without opening a mic
/// or sending a request to Meta. This entire probe is excluded from releases.
@MainActor enum DevelopmentSpeechProbe {
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.environment["AVATODO_SPEECH_PAUSE_PROBE"] == "1" else { return }
        unsetenv("AVATODO_SPEECH_PAUSE_PROBE")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SpeechPauseProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report: [String: Any] = [:], updates: [[String: Any]] = []
        let recognition = PhoneRecognition(), renderer = PhoneSpeechRenderer()
        defer { recognition.cancel(); renderer.cancel() }
        do {
            var pcm = Data(repeating: 0, count: 3_200)
            for (i, phrase) in ["Good morning", "How are you", "today"].enumerated() {
                let clip = try await renderer.render(phrase, preferredID: nil, language: "en-US")
                let url = folder.appendingPathComponent("fixture-\(i).m4a")
                try clip.data.write(to: url)
                let file = try AVAudioFile(forReading: url)
                guard let encoder = RelayPCMEncoder(inputFormat: file.processingFormat),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { throw AudioFailure.conversionFailed }
                while file.framePosition < file.length {
                    try file.read(into: buffer)
                    guard let data = encoder.encode(buffer) else { throw AudioFailure.conversionFailed }
                    pcm.append(data)
                }
                pcm.append(Data(repeating: 0, count: 64_000))
                try? FileManager.default.removeItem(at: url)
            }
            recognition.debugSnapshot = { text, starts, lengths, final in
                updates.append(["fixture_text": text, "starts": starts, "durations": lengths, "final": final])
            }
            var failed: String?
            try await recognition.start(partial: { report["last_partial"] = $0 }, failed: { failed = $0.localizedDescription })
            report["on_device"] = recognition.onDevice
            for offset in stride(from: 0, to: pcm.count, by: 3200) {
                try recognition.append(pcm.subdata(in: offset..<min(offset+3200, pcm.count)), sampleRate: 16_000)
                try await Task.sleep(for: .milliseconds(100))
                if failed != nil { break }
            }
            report["final_text"] = try await recognition.finish()
            report["service_failure"] = failed
            report["completed"] = true
        } catch { report["completed"] = false; report["failure"] = String(describing: error) }
        report["updates"] = updates
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("results.json"), options: .atomic)
        }
    }
}
#endif
