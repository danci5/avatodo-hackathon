import Foundation
import Testing
@testable import AvatodoCore

private func timed(_ text: String, start: Double, step: Double = 0.4) -> [SpeechTranscriptSegment] {
    let source = text as NSString
    var search = NSRange(location: 0, length: source.length)
    return text.split(separator: " ").enumerated().map { index, word in
        let range = source.range(of: String(word), range: search)
        search = NSRange(location: range.location + range.length, length: source.length-range.location-range.length)
        return SpeechTranscriptSegment(location: range.location, length: range.length,
                                       timestamp: start + Double(index)*step, duration: step*0.8)
    }
}
private func zero(_ text: String) -> [SpeechTranscriptSegment] {
    timed(text, start: 0).map { .init(location: $0.location, length: $0.length, timestamp: 0, duration: 0) }
}

@Test func pausesKeepEarlierPhrasesFromRealAppleCallbackShape() throws {
    var transcript = SpeechTranscript(), finalization = SpeechFinalization()
    try finalization.submitAudio(sampleCount: 160_000)
    #expect(transcript.receive("Good", segments: zero("Good")) == "Good")
    #expect(transcript.receive("Good morning", segments: zero("Good morning")) == "Good morning")
    _ = transcript.receive("Good morning", segments: timed("Good morning", start: 0))
    #expect(transcript.receive("How", segments: zero("How")) == "Good morning How")
    #expect(transcript.receive("How are you", segments: zero("How are you")) == "Good morning How are you")
    _ = transcript.receive("How are you", segments: timed("How are you", start: 2.64))
    #expect(transcript.receive("Today", segments: zero("Today")) == "Good morning How are you Today")
    let full = transcript.receive("Today", segments: timed("Today", start: 5.52))
    finalization.receive(text: full, isFinal: true, issue: nil)
    #expect(try finalization.finalizedText() == "Good morning How are you Today")
}

@Test func partialAndTimedCorrectionsReplaceTheirOwnAudioWindow() {
    var transcript = SpeechTranscript()
    _ = transcript.receive("Buy mill", segments: zero("Buy mill"))
    #expect(transcript.receive("Buy milk", segments: zero("Buy milk")) == "Buy milk")
    _ = transcript.receive("Buy milk", segments: timed("Buy milk", start: 0))
    #expect(transcript.receive("Buy oat milk", segments: timed("Buy oat milk", start: 0)) == "Buy oat milk")
    _ = transcript.receive("and bread", segments: timed("and bread", start: 3))
    #expect(transcript.receive("Buy oat milk and bread.", segments: timed("Buy oat milk and bread.", start: 0)) == "Buy oat milk and bread.")
}

@Test func repeatedWordsAreKeptAtDifferentAudioTimesAndDuplicatesDoNotMultiply() {
    var transcript = SpeechTranscript()
    _ = transcript.receive("No", segments: timed("No", start: 0))
    #expect(transcript.receive("No", segments: timed("No", start: 2)) == "No No")
    #expect(transcript.receive("No", segments: timed("No", start: 2)) == "No No")
}

@Test func aCumulativeUntimedHypothesisDoesNotRepeatTheRetainedPrefix() {
    var transcript = SpeechTranscript()
    _ = transcript.receive("Good morning", segments: timed("Good morning", start: 0))
    #expect(transcript.receive("Good morning how", segments: zero("Good morning how")) == "Good morning how")
    #expect(transcript.receive("", segments: []) == "Good morning")
}

@Test func timedSlidingWindowKeepsWordsBeforeTheRevisedRange() {
    var transcript = SpeechTranscript()
    _ = transcript.receive("Add milk and eggs", segments: timed("Add milk and eggs", start: 0))
    #expect(transcript.receive("and bread", segments: timed("and bread", start: 0.8)) == "Add milk and bread")
}

@Test func punctuationUnicodeAndInvalidRangesStaySafe() {
    var transcript = SpeechTranscript()
    _ = transcript.receive("Café 🥛.", segments: timed("Café 🥛.", start: 0))
    #expect(transcript.receive("Thank you!", segments: timed("Thank you!", start: 3)) == "Café 🥛. Thank you!")
    let invalid = SpeechTranscriptSegment(location: Int.max, length: 1, timestamp: 4, duration: 1)
    #expect(transcript.receive("More", segments: [invalid]) == "Café 🥛. Thank you! More")
    var chinese = SpeechTranscript()
    #expect(chinese.receive("你好世界", segments: [
        .init(location: 0, length: 2, timestamp: 0, duration: 0.4),
        .init(location: 2, length: 2, timestamp: 0.5, duration: 0.4)
    ]) == "你好世界")
}

@Test func assembledPartialOrServiceErrorStillCannotAuthorizeAMutation() throws {
    var transcript = SpeechTranscript(), result = SpeechFinalization()
    try result.submitAudio(sampleCount: 16_000)
    _ = transcript.receive("Add milk", segments: timed("Add milk", start: 0))
    let accumulated = transcript.receive("and eggs", segments: zero("and eggs"))
    result.receive(text: accumulated, isFinal: false, issue: nil)
    #expect(throws: SpeechRecognitionFailure.finalizationTimedOut) { try result.finalizedText() }
    let issue = SpeechServiceIssue(domain: "kAFAssistantErrorDomain", code: 1101)
    result.receive(text: accumulated, isFinal: true, issue: issue)
    #expect(throws: SpeechRecognitionFailure.service(issue)) { try result.finalizedText() }
    #expect(SpeechTranscript().text.isEmpty)
}

@Test func twentyPausedPhrasesRemainInOneCapture() {
    var transcript = SpeechTranscript()
    for i in 1...20 { _ = transcript.receive("Item \(i)", segments: timed("Item \(i)", start: Double(i)*2)) }
    #expect(transcript.text == (1...20).map { "Item \($0)" }.joined(separator: " "))
}
