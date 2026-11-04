import Foundation

enum WatchVoiceMode: String, Codable, Sendable { case iPhone, watch }
enum CompanionReaction: String, Codable, Sendable { case laugh, dance }
struct WatchVoiceDescriptor: Codable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: Int
}

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
    // Optional for older paired apps. Setup is cancellable capture preparation,
    // not an agent request, so its primary control already presents Done.
    var preparingToListen: Bool?
    var controlsPhase: CompanionPhase {
        phase == .thinking && preparingToListen == true ? .listening : phase
    }
    var preferredVoiceID: String?
    var preferredVoiceLanguage: String?
    var watchVoiceMode: WatchVoiceMode?
    var preferredWatchVoiceID: String?
    var preferredWatchVoiceLanguage: String?
    var replyAudioExpected: Bool?
    var replyAudioID: UUID?
    var reaction: CompanionReaction?
    var reactionID: UUID?
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
        case begin, finish, cancel, text, undo, startFresh, playbackEnded, stopSpeaking, status, character, speechFallback, dance
    }
    var kind: Kind
    var requestID: UUID
    var text: String?
    var receiptID: UUID?
    var packetCount: Int?
    var endingPlaybackID: UUID?
    var supportsCharacterAnimations: Bool? = nil
    var supportsPhoneReplyAudio: Bool? = nil
    var availableVoices: [WatchVoiceDescriptor]? = nil
    var reactionID: UUID? = nil
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
    var animationLayout: CharacterAnimationLayout? = nil
}

enum CharacterAnimationLayout: String, Codable, Sendable {
    case ninePoseV1, sixteenPoseV1, twentyPoseV1
    var columns: Int { switch self { case .ninePoseV1: 3; case .sixteenPoseV1: 4; case .twentyPoseV1: 5 } }
    var rows: Int { self == .twentyPoseV1 ? 4 : columns }
    var cellSide: Int { self == .twentyPoseV1 ? 320 : 384 }
    var width: Int { columns * cellSide }
    var height: Int { rows * cellSide }
    var frameCount: Int { columns * rows }
}
