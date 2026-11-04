import Foundation

enum CompanionPhase: String, Codable, Sendable {
    case ready, listening, thinking, speaking, confirmed, error
    var actionTitle: String {
        switch self {
        case .ready, .confirmed, .error: "Talk"
        case .listening: "Done"
        case .thinking: "Cancel"
        case .speaking: "Stop speaking"
        }
    }
    var isIdle: Bool { self == .ready || self == .confirmed || self == .error }
    var title: String {
        switch self {
        case .ready: "Ready when you are"
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
        case .confirmed: "Saved"
        case .error: "Needs attention"
        }
    }
}

struct CompanionViewState: Codable, Sendable, Equatable {
    var phase: CompanionPhase = .ready
    var caption = "Ready when you are"
    var text = ""
    var resultIsMutation = false
    var noteTitle: String?
    var noteID: UUID?
    var undoReceiptID: UUID?
    var replyDevice = "phone"
    var requestID: UUID?
    var hasModelKey = false
    var hasDataSharingConsent: Bool?
    var speechReady = false
    var preferredVoiceID: String?
    var preferredVoiceLanguage: String?
    var characterID: UUID?
    var characterName = "Ava"
    var epoch = UUID()
    var sequence = 0
    var sessionExpiresAt: Date?
    var undoExpiresAt: Date?
    var updatedAt = Date()
}

struct WatchCommand: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case begin, finish, cancel, text, undo, startFresh, playbackEnded, stopSpeaking, status, character
    }
    var kind: Kind
    var requestID: UUID
    var text: String?
    var receiptID: UUID?
    var packetCount: Int?
    var endingPlaybackID: UUID?
}

/// Wire audio is mono signed Int16 little-endian PCM at 16 kHz, never persisted.
struct VoiceFrame: Codable, Sendable {
    let requestID: UUID
    let sequence: Int
    let sampleRate: Double
    let samples: Data
}

struct CharacterManifest: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var sha256: String
    var generatedAt: Date
    var sourceModel: String
    var description: String? = nil
}
