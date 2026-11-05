import Foundation

/// A word's UTF-16 position in one Apple transcription and its position in the
/// capture's audio stream. Partial hypotheses can have all-zero timing.
public struct SpeechTranscriptSegment: Sendable {
    public let location: Int
    public let length: Int
    public let timestamp: Double
    public let duration: Double
    public init(location: Int, length: Int, timestamp: Double, duration: Double) {
        self.location = location; self.length = length
        self.timestamp = timestamp; self.duration = duration
    }
}

/// One capture, held only in RAM. On-device Apple recognition may publish a
/// timed phrase, then restart its next partial hypothesis at an all-zero range.
/// Retain timed words; replace overlapping revisions rather than appending each
/// callback. Only SpeechFinalization can authorize submission after Done.
public struct SpeechTranscript: Sendable {
    private struct Word: Sendable {
        let fragment: String
        let start: Double
        let end: Double
        let beginsWindow: Bool
    }
    private var words: [Word] = []
    private var partial = ""
    public init() {}

    @discardableResult public mutating func receive(_ text: String, segments: [SpeechTranscriptSegment]) -> String {
        let source = text as NSString
        let timed = !segments.isEmpty && segments.contains { $0.duration > 0 } &&
            segments.allSatisfy { $0.location >= 0 && $0.location <= source.length && $0.length > 0 &&
                $0.length <= source.length - $0.location && $0.timestamp.isFinite && $0.timestamp >= 0 &&
                $0.duration.isFinite && $0.duration >= 0 } &&
            zip(segments, segments.dropFirst()).allSatisfy { $0.location + $0.length <= $1.location && $0.timestamp <= $1.timestamp }
        if timed, let first = segments.first {
            // A final/corrected cumulative result can cover previous phrases.
            // Replace that interval, retaining only words strictly before it.
            words = Array(words.prefix { $0.start < first.timestamp - 0.03 && $0.end <= first.timestamp + 0.03 })
            for (index, segment) in segments.enumerated() {
                let lower = index == 0 ? 0 : segment.location
                let upper = index + 1 < segments.count ? segments[index+1].location : source.length
                let fragment = source.substring(with: NSRange(location: lower, length: upper-lower))
                words.append(Word(fragment: fragment, start: segment.timestamp, end: segment.timestamp + segment.duration,
                                  beginsWindow: index == 0))
            }
            partial = ""
        } else { partial = text }
        return self.text
    }
    public var text: String {
        let stable = words.reduce("") { $1.beginsWindow ? join($0, $1.fragment) : $0 + $1.fragment }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let current = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stable.isEmpty else { return current }
        guard !current.isEmpty else { return stable }
        // Some engines keep returning a cumulative hypothesis instead of a new
        // phrase. Do not duplicate its already retained leading text. Timing on
        // the subsequent settled result distinguishes intentional repetitions.
        if current.hasPrefix(stable) { return current }
        if stable.hasPrefix(current) { return stable }
        return join(stable, current)
    }
    private func join(_ left: String, _ right: String) -> String {
        guard let last = left.last, let first = right.first else { return left + right }
        if last.isWhitespace || first.isWhitespace || ",.;:!?…".contains(first) { return left + right }
        return left + " " + right
    }
}
