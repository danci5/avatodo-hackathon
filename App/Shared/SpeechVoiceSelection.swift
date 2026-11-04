import Foundation

struct SpeechVoiceOption: Identifiable, Equatable, Sendable {
    enum Quality: Int, Sendable {
        case standard = 1, enhanced = 2, premium = 3
        var label: String {
            switch self { case .standard: "Standard"; case .enhanced: "Enhanced"; case .premium: "Premium" }
        }
    }
    let id: String
    let name: String
    let language: String
    let quality: Quality
    var isPersonal = false
    var isNovelty = false

    var label: String {
        let languageName = Locale.current.localizedString(forIdentifier: language) ?? language
        return "\(name) · \(quality.label) · \(languageName)"
    }
}

enum SpeechVoiceSelection {
    static func languageMatches(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs).split(separator: "-").first
        let right = normalized(rhs).split(separator: "-").first
        return left != nil && left == right
    }

    static func select(preferredID: String?, language: String, voices: [SpeechVoiceOption],
                       systemDefaultID: String? = nil) -> SpeechVoiceOption? {
        let ordinary = voices.filter { !$0.isPersonal }
        if let preferredID, let selected = ordinary.first(where: { $0.id == preferredID }) { return selected }
        return ordinary.filter { !$0.isNovelty && languageMatches($0.language, language) }.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
            let leftDialect = normalized(lhs.language) == normalized(language)
            let rightDialect = normalized(rhs.language) == normalized(language)
            if leftDialect != rightDialect { return leftDialect }
            let leftDefault = lhs.id == systemDefaultID, rightDefault = rhs.id == systemDefaultID
            if leftDefault != rightDefault { return leftDefault }
            return lhs.id < rhs.id
        }.first
    }

    private static func normalized(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
