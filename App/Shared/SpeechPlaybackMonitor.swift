import Foundation

enum SpeechPlaybackEnd: Equatable, Sendable {
    case finished, interrupted, unavailable
    var failed: Bool { self != .finished }
}

/// No text is retained. This bounds missing Apple callbacks without treating a
/// submitted utterance as proof that sound started or reached the listener.
struct SpeechPlaybackMonitor {
    let requestedAt: TimeInterval
    let maximumDuration: TimeInterval
    private(set) var startedAt: TimeInterval?
    private(set) var lastProgressAt: TimeInterval?

    init(now: TimeInterval, characterCount: Int) {
        requestedAt = now
        maximumDuration = min(180, max(20, Double(characterCount) / 8 + 10))
    }
    mutating func started(now: TimeInterval) {
        if startedAt == nil { startedAt = now }
        lastProgressAt = now
    }
    mutating func progressed(now: TimeInterval) { started(now: now) }
    func outcome(now: TimeInterval, isSpeaking: Bool, isPaused: Bool) -> SpeechPlaybackEnd? {
        guard let startedAt else { return now - requestedAt >= 5 ? .unavailable : nil }
        if !isSpeaking && !isPaused && now - startedAt >= 1 { return .finished }
        if now - (lastProgressAt ?? startedAt) >= 15 || now - requestedAt >= maximumDuration { return .unavailable }
        return nil
    }
}
