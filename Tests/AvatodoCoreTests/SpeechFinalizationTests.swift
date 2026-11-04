import Testing
@testable import AvatodoCore

@Test func emptyRecordingQuietlyFinishesWithoutARequest() throws {
    #expect(try SpeechFinalization().finalizedTextOrEmpty() == nil)
    var speech = SpeechFinalization()
    try speech.submitAudio(sampleCount: 1600)
    #expect(try speech.finalizedTextOrEmpty() == nil)
    speech.receive(text: " \n ", isFinal: true, issue: nil)
    #expect(try speech.finalizedTextOrEmpty() == nil)
    speech.receive(text: nil, isFinal: false,
        issue: SpeechServiceIssue(domain: "kAFAssistantErrorDomain", code: 1110))
    #expect(try speech.finalizedTextOrEmpty() == nil)
}

@Test func emptyRecordingDoesNotHideRealServiceFailuresOrPartialWords() throws {
    for code in [1101, 1110] {
        var speech = SpeechFinalization()
        try speech.submitAudio(sampleCount: 1600)
        let issue = SpeechServiceIssue(domain: "kAFAssistantErrorDomain", code: code)
        speech.receive(text: code == 1110 ? "Add eggs" : nil, isFinal: true, issue: issue)
        #expect(throws: SpeechRecognitionFailure.service(issue)) { try speech.finalizedTextOrEmpty() }
    }
    var partial = SpeechFinalization()
    try partial.submitAudio(sampleCount: 1600)
    partial.receive(text: "Add eggs", isFinal: false, issue: nil)
    #expect(throws: SpeechRecognitionFailure.finalizationTimedOut) { try partial.finalizedTextOrEmpty() }
}

@Test func partialSpeechNeverAuthorizesAnAgentTurn() throws {
    var speech = SpeechFinalization()
    try speech.submitAudio(sampleCount: 1600)
    speech.receive(text: "Add eggs", isFinal: false, issue: nil)
    #expect(throws: SpeechRecognitionFailure.finalizationTimedOut) { try speech.finalizedText() }
    speech.receive(text: "  Add eggs and bread.  ", isFinal: true, issue: nil)
    #expect(try speech.finalizedText() == "Add eggs and bread.")
}

@Test func speechErrorWinsOverFinalTextAndLaterCallbacks() throws {
    var speech = SpeechFinalization()
    try speech.submitAudio(sampleCount: 1600)
    let issue = SpeechServiceIssue(domain: "kAFAssistantErrorDomain", code: 1101)
    speech.receive(text: "A final-looking request", isFinal: true, issue: issue)
    speech.receive(text: "A late final result", isFinal: true, issue: nil)
    #expect(throws: SpeechRecognitionFailure.service(issue)) { try speech.finalizedText() }
}

@Test func finalSpeechRequiresActualAudioAndRecognizedWords() throws {
    var noAudio = SpeechFinalization()
    noAudio.receive(text: "A result without submitted audio", isFinal: true, issue: nil)
    #expect(throws: SpeechRecognitionFailure.noAudio) { try noAudio.finalizedText() }
    var noWords = SpeechFinalization()
    try noWords.submitAudio(sampleCount: 1600)
    noWords.receive(text: " \n ", isFinal: true, issue: nil)
    #expect(throws: SpeechRecognitionFailure.noWords) { try noWords.finalizedText() }
}

@Test func speechDiagnosticsCannotEchoUnknownDomainsOrTranscription() throws {
    let privateText = "fixture-user-words-and-arbitrary-domain"
    let issue = SpeechServiceIssue(domain: privateText, code: 42)
    #expect(issue.domain == "AppleSpeech")
    let failure = SpeechRecognitionFailure.service(issue)
    #expect(failure.errorDescription?.contains("42") == true)
    #expect(failure.errorDescription?.contains(privateText) == false)
    var speech = SpeechFinalization()
    try speech.submitAudio(sampleCount: 1600)
    speech.receive(text: privateText, isFinal: false, issue: issue)
    #expect(throws: failure) { try speech.finalizedText() }
}

@Test func speechCannotCommitAnEarlierFinalAfterAdditionalAudio() throws {
    var speech = SpeechFinalization()
    try speech.submitAudio(sampleCount: 1600)
    speech.receive(text: "First segment", isFinal: true, issue: nil)
    #expect(throws: SpeechRecognitionFailure.audioAfterFinal) { try speech.submitAudio(sampleCount: 1600) }
    #expect(throws: SpeechRecognitionFailure.audioAfterFinal) { try speech.finalizedText() }
}

@Test func lateSpeechServiceErrorInvalidatesAnUncommittedFinal() throws {
    var speech = SpeechFinalization()
    try speech.submitAudio(sampleCount: 1600)
    speech.receive(text: "Do not commit this", isFinal: true, issue: nil)
    let issue = SpeechServiceIssue(domain: "kLSRErrorDomain", code: 301)
    speech.receive(text: nil, isFinal: false, issue: issue)
    #expect(throws: SpeechRecognitionFailure.service(issue)) { try speech.finalizedText() }
}
