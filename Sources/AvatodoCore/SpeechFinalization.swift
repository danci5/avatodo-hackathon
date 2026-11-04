import Foundation

/// Only a known service name and numeric code may leave Apple's speech callback.
public struct SpeechServiceIssue: Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        let known = ["kAFAssistantErrorDomain", "kLSRErrorDomain", "SFSpeechErrorDomain",
                     "SiriSpeechErrorDomain", "NSURLErrorDomain", "NSOSStatusErrorDomain",
                     "AVFoundationErrorDomain", "NSCocoaErrorDomain"]
        self.domain = known.contains(domain) ? domain : "AppleSpeech"
        self.code = code
    }
}

public enum SpeechRecognitionFailure: Error, Equatable, Sendable, LocalizedError {
    case unavailable, noAudio, noWords, finalizationTimedOut, audioAfterFinal
    case service(SpeechServiceIssue)

    /// Apple's no-speech outcome is an empty turn, not an actionable transcript.
    public var isEmptyInput: Bool {
        switch self {
        case .noAudio, .noWords: true
        case let .service(issue): issue.domain == "kAFAssistantErrorDomain" && issue.code == 1110
        default: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple speech recognition is unavailable for the current language. Try again or type on iPhone."
        case .noAudio:
            "No microphone audio reached speech recognition. Nothing was sent. Try again or type on iPhone."
        case .noWords:
            "Audio arrived, but no words were recognized. Nothing was sent. Try again."
        case .finalizationTimedOut:
            "Audio arrived, but Apple speech did not finish in time. Nothing was sent. Try again or type on iPhone."
        case .audioAfterFinal:
            "Speech recognition ended before recording finished. Nothing was sent. Try a shorter request."
        case let .service(issue):
            "Apple speech stopped (\(issue.domain), code \(issue.code)). Nothing was sent. Try again or type on iPhone."
        }
    }
}

/// RAM-only speech state. Partial or errored results can never authorize an agent turn.
public struct SpeechFinalization: Sendable {
    public private(set) var submittedSamples = 0
    public private(set) var text = ""
    public private(set) var isFinal = false
    public private(set) var failure: SpeechRecognitionFailure?
    public var resolved: Bool { isFinal || failure != nil }
    public var hasRecognizedWords: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public init() {}

    public mutating func submitAudio(sampleCount: Int) throws {
        if let failure { throw failure }
        guard !isFinal else { failure = .audioAfterFinal; throw SpeechRecognitionFailure.audioAfterFinal }
        guard sampleCount > 0 else { return }
        submittedSamples += sampleCount
    }

    public mutating func receive(text: String?, isFinal: Bool, issue: SpeechServiceIssue?) {
        // An error wins even when the same callback also contains a final result.
        if let issue {
            if let text { self.text = text }
            failure = .service(issue); return
        }
        guard failure == nil, !self.isFinal else { return }
        if let text { self.text = text }
        self.isFinal = isFinal
    }

    public func finalizedText() throws -> String {
        if let failure { throw failure }
        guard submittedSamples > 0 else { throw SpeechRecognitionFailure.noAudio }
        guard isFinal else { throw SpeechRecognitionFailure.finalizationTimedOut }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw SpeechRecognitionFailure.noWords }
        return words
    }

    public func finalizedTextOrEmpty() throws -> String? {
        do { return try finalizedText() }
        catch let failure as SpeechRecognitionFailure {
            if !hasRecognizedWords && (failure.isEmptyInput || failure == .finalizationTimedOut) { return nil }
            throw failure
        }
    }
}
