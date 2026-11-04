import Foundation
import CryptoKit

struct ReplyAudioManifest: Codable, Equatable, Sendable {
    static let maximumBytes = 2_000_000
    let id: UUID
    let requestID: UUID
    let sha256: String
    let totalBytes: Int
    let duration: Double
}
struct ReplyAudioChunk: Codable, Sendable {
    static let payloadBytes = 24_000
    let manifest: ReplyAudioManifest
    let index: Int
    let count: Int
    let bytes: Data
}
struct CompletedReplyAudio: Sendable { let manifest: ReplyAudioManifest; let data: Data }

/// One reply in bounded RAM. Selection and closing are explicit so a late clip
/// cannot speak after Stop, local fallback or a newer conversation turn.
struct ReplyAudioAssembler {
    private var requestID: UUID?
    private var selectedID: UUID?
    private var closed = false
    private var manifest: ReplyAudioManifest?
    private var chunks: [Int: Data] = [:]
    private(set) var bufferedBytes = 0
    mutating func begin(_ requestID: UUID) {
        self = ReplyAudioAssembler(); self.requestID = requestID
    }
    mutating func close() { closed = true; chunks.removeAll(); manifest = nil; bufferedBytes = 0 }
    mutating func select(_ id: UUID, requestID: UUID) throws -> CompletedReplyAudio? {
        guard !closed, self.requestID == requestID else { return nil }
        selectedID = id
        if manifest?.id != id { manifest = nil; chunks.removeAll(); bufferedBytes = 0 }
        return try complete()
    }
    mutating func accept(_ chunk: ReplyAudioChunk) throws -> CompletedReplyAudio? {
        guard !closed, chunk.manifest.requestID == requestID else { return nil }
        let m = chunk.manifest
        guard m.totalBytes > 0, m.totalBytes <= ReplyAudioManifest.maximumBytes,
              m.duration.isFinite, m.duration > 0, m.duration <= 45,
              m.sha256.count == 64, m.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              chunk.count == (m.totalBytes + ReplyAudioChunk.payloadBytes - 1) / ReplyAudioChunk.payloadBytes,
              chunk.index >= 0, chunk.index < chunk.count,
              chunk.bytes.count == min(ReplyAudioChunk.payloadBytes, m.totalBytes - chunk.index * ReplyAudioChunk.payloadBytes)
        else { throw ReplyAudioFailure.invalid }
        if let selectedID, selectedID != m.id { return nil }
        if let manifest, manifest != m { throw ReplyAudioFailure.invalid }
        manifest = m
        if let duplicate = chunks[chunk.index] {
            guard duplicate == chunk.bytes else { close(); throw ReplyAudioFailure.invalid }
            return nil
        }
        chunks[chunk.index] = chunk.bytes; bufferedBytes += chunk.bytes.count
        return try complete()
    }
    private mutating func complete() throws -> CompletedReplyAudio? {
        guard let manifest, manifest.id == selectedID,
              chunks.count == (manifest.totalBytes + ReplyAudioChunk.payloadBytes - 1) / ReplyAudioChunk.payloadBytes else { return nil }
        var data = Data(); data.reserveCapacity(manifest.totalBytes)
        for index in 0..<chunks.count {
            guard let part = chunks[index] else { throw ReplyAudioFailure.invalid }; data.append(part)
        }
        guard data.count == manifest.totalBytes, Self.digest(data) == manifest.sha256 else {
            close(); throw ReplyAudioFailure.invalid
        }
        close(); return CompletedReplyAudio(manifest: manifest, data: data)
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
enum ReplyAudioFailure: Error, Sendable { case invalid, unavailable, tooLong, timedOut }
