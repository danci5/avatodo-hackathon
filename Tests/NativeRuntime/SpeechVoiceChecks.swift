import Foundation

@main enum SpeechVoiceChecks {
    static func voice(_ id: String, _ language: String, _ quality: SpeechVoiceOption.Quality,
                      personal: Bool = false, novelty: Bool = false) -> SpeechVoiceOption {
        SpeechVoiceOption(id: id, name: id, language: language, quality: quality,
                          isPersonal: personal, isNovelty: novelty)
    }
    static func main() throws {
        let standard = voice("standard", "en-US", .standard)
        let enhanced = voice("enhanced", "en-US", .enhanced)
        let premium = voice("premium", "en-GB", .premium)
        let all = [standard, enhanced, premium, voice("other-language", "de-DE", .premium)]
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "en-US", voices: all)?.id == premium.id)
        precondition(SpeechVoiceSelection.select(preferredID: standard.id, language: "en-US", voices: all)?.id == standard.id)
        print("PASS: Automatic chooses language-matching quality; explicit installed choice overrides it")

        let dialect = voice("dialect", "en-US", .premium)
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "en_US", voices: [premium, dialect])?.id == dialect.id)
        let system = voice("system", "en-US", .standard), lexical = voice("aaa", "en-US", .standard)
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "en-US", voices: [lexical, system], systemDefaultID: system.id)?.id == system.id)
        print("PASS: same-quality dialect and Apple default break ties before deterministic identifiers")

        let personal = voice("personal", "en-US", .premium, personal: true)
        let novelty = voice("novelty", "en-US", .premium, novelty: true)
        let safe = [personal, novelty, standard]
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "en-US", voices: safe)?.id == standard.id)
        precondition(SpeechVoiceSelection.select(preferredID: personal.id, language: "en-US", voices: safe)?.id == standard.id)
        precondition(SpeechVoiceSelection.select(preferredID: novelty.id, language: "en-US", voices: safe)?.id == novelty.id)
        precondition(SpeechVoiceSelection.select(preferredID: personal.id, language: "en-US", voices: [personal]) == nil)
        print("PASS: Personal voices never selected; novelty only follows an explicit user choice")

        let receiver = [voice("watch-enhanced", "en-GB", .enhanced), voice("unrelated", "fr-FR", .premium)]
        precondition(SpeechVoiceSelection.select(preferredID: "missing-phone-voice", language: "en-US", voices: receiver)?.id == "watch-enhanced")
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "ja-JP", voices: receiver) == nil)
        let tie = [voice("b", "en-GB", .enhanced), voice("a", "en-GB", .enhanced)]
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "en-US", voices: tie)?.id == "a")
        precondition(SpeechVoiceSelection.select(preferredID: nil, language: "en-US", voices: tie.reversed())?.id == "a")
        print("PASS: missing cross-device selection falls back within language; no match fails safely")

        var state = CompanionViewState()
        state.preferredVoiceID = premium.id; state.preferredVoiceLanguage = premium.language
        let encoded = try JSONEncoder().encode(state)
        let roundTrip = try JSONDecoder().decode(CompanionViewState.self, from: encoded)
        precondition(roundTrip.preferredVoiceID == premium.id && roundTrip.preferredVoiceLanguage == premium.language)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "preferredVoiceID"); legacy.removeValue(forKey: "preferredVoiceLanguage")
        let old = try JSONDecoder().decode(CompanionViewState.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.preferredVoiceID == nil && old.preferredVoiceLanguage == nil)
        print("PASS: voice ID/language round-trip and older Watch state without those fields decodes")
    }
}
