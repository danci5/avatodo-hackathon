import Foundation

@main enum SpeechPlaybackChecks {
    static func main() throws {
        var missing = SpeechPlaybackMonitor(now: 100, characterCount: 400)
        precondition(missing.outcome(now: 104.9, isSpeaking: true, isPaused: false) == nil)
        precondition(missing.outcome(now: 105, isSpeaking: true, isPaused: false) == .unavailable)
        print("PASS missing start callback cannot leave Stop speaking indefinitely")

        missing.started(now: 101)
        precondition(missing.outcome(now: 101.5, isSpeaking: false, isPaused: false) == nil)
        precondition(missing.outcome(now: 102, isSpeaking: false, isPaused: false) == .finished)
        missing.progressed(now: 110)
        precondition(missing.outcome(now: 124, isSpeaking: true, isPaused: false) == nil)
        precondition(missing.outcome(now: 125, isSpeaking: true, isPaused: false) == .unavailable)
        print("PASS vanished completion and stalled synthesis have bounded recovery")

        var long = SpeechPlaybackMonitor(now: 0, characterCount: 8000)
        for time in stride(from: 1.0, to: 180, by: 1) {
            long.progressed(now: time)
            precondition(long.outcome(now: time, isSpeaking: true, isPaused: false) == nil)
        }
        precondition(long.outcome(now: 180, isSpeaking: true, isPaused: false) == .unavailable)
        print("PASS hard playback ceiling remains bounded even with repeated progress callbacks")

        let previous = UUID(), next = UUID()
        let command = WatchCommand(kind: .begin, requestID: next, endingPlaybackID: previous)
        let wire = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: wire)
        precondition(decoded.endingPlaybackID == previous && decoded.requestID == next)
        let old = Data("{\"kind\":\"playbackEnded\",\"requestID\":\"\(previous.uuidString)\"}".utf8)
        let legacy = try JSONDecoder().decode(WatchCommand.self, from: old)
        precondition(legacy.endingPlaybackID == nil)
        print("PASS playback acknowledgement survives the next turn and legacy messages remain readable")
    }
}
