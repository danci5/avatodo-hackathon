import Foundation
import CryptoKit

/// Foreground image chunks stay below WatchConnectivity's message limit.
struct CharacterChunk: Codable, Sendable, Equatable {
    static let maximumImageBytes = 4_000_000
    static let payloadBytes = 24_000
    let transferID: UUID
    let manifest: CharacterManifest
    let index: Int
    let count: Int
    let totalBytes: Int
    let bytes: Data
}

struct CompletedCharacterTransfer: Sendable {
    let manifest: CharacterManifest
    let image: Data
}

/// At most one bounded image is assembled in RAM. A complete image is released
/// only when authoritative phone state selects that character, including when
/// the chunks arrive before the state message. Default resets reject older data.
struct CharacterChunkAssembler: Sendable {
    private struct Assembly: Sendable {
        let transferID: UUID
        let manifest: CharacterManifest
        let count: Int
        let totalBytes: Int
        var chunks: [Int: Data] = [:]
        var receivedBytes = 0
        var complete: Data?
    }
    private var assembly: Assembly?
    private var selectedID: UUID?
    private var selectionDate = Date.distantPast
    private var retiredTransfers: [UUID] = []
    var bufferedBytes: Int { assembly?.receivedBytes ?? 0 }

    mutating func select(_ id: UUID?, at date: Date) -> CompletedCharacterTransfer? {
        guard date >= selectionDate else { return nil }
        selectedID = id; selectionDate = date
        if let current = assembly, current.manifest.id != id, current.manifest.generatedAt <= date {
            retire(current.transferID); assembly = nil
        }
        return releaseSelectedImage()
    }

    mutating func accept(_ chunk: CharacterChunk) throws -> CompletedCharacterTransfer? {
        guard chunk.totalBytes > 0, chunk.totalBytes <= CharacterChunk.maximumImageBytes,
              chunk.count == (chunk.totalBytes + CharacterChunk.payloadBytes - 1) / CharacterChunk.payloadBytes,
              chunk.index >= 0, chunk.index < chunk.count,
              chunk.bytes.count == min(CharacterChunk.payloadBytes, chunk.totalBytes - chunk.index * CharacterChunk.payloadBytes),
              chunk.manifest.sha256.count == 64,
              chunk.manifest.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              chunk.manifest.name.count <= 40, chunk.manifest.sourceModel.count <= 100,
              (chunk.manifest.description?.count ?? 0) <= 2_000 else {
            throw CharacterTransferError.invalidChunk
        }
        guard !retiredTransfers.contains(chunk.transferID) else { return nil }
        if chunk.manifest.id != selectedID, chunk.manifest.generatedAt <= selectionDate { return nil }
        if let current = assembly, current.transferID != chunk.transferID {
            // A late packet from an older character must not evict a newer transfer.
            guard chunk.manifest.id == selectedID || chunk.manifest.generatedAt >= current.manifest.generatedAt else { return nil }
            retire(current.transferID); assembly = nil
        }
        if assembly == nil {
            assembly = Assembly(transferID: chunk.transferID, manifest: chunk.manifest,
                                count: chunk.count, totalBytes: chunk.totalBytes)
        }
        guard var current = assembly, current.manifest == chunk.manifest,
              current.count == chunk.count, current.totalBytes == chunk.totalBytes else {
            throw CharacterTransferError.invalidChunk
        }
        if current.complete != nil { return releaseSelectedImage() }
        if let previous = current.chunks[chunk.index] {
            guard previous == chunk.bytes else { throw CharacterTransferError.conflictingChunk }
            return nil
        }
        current.chunks[chunk.index] = chunk.bytes
        current.receivedBytes += chunk.bytes.count
        guard current.receivedBytes <= current.totalBytes else { throw CharacterTransferError.invalidChunk }
        if current.chunks.count == current.count {
            var image = Data(); image.reserveCapacity(current.totalBytes)
            for index in 0..<current.count {
                guard let bytes = current.chunks.removeValue(forKey: index) else { throw CharacterTransferError.invalidChunk }
                image.append(bytes)
            }
            guard image.count == current.totalBytes,
                  SHA256.hash(data: image).map({ String(format: "%02x", $0) }).joined() == current.manifest.sha256 else {
                retire(current.transferID); assembly = nil
                throw CharacterTransferError.hashMismatch
            }
            current.complete = image
        }
        assembly = current
        return releaseSelectedImage()
    }
    private mutating func releaseSelectedImage() -> CompletedCharacterTransfer? {
        guard let current = assembly, current.manifest.id == selectedID, let image = current.complete else { return nil }
        retire(current.transferID); assembly = nil
        return CompletedCharacterTransfer(manifest: current.manifest, image: image)
    }
    private mutating func retire(_ id: UUID) {
        retiredTransfers.append(id)
        if retiredTransfers.count > 24 { retiredTransfers.removeFirst(retiredTransfers.count - 24) }
    }
}
enum CharacterTransferError: Error, Sendable {
    case invalidChunk, conflictingChunk, hashMismatch, unavailable, timedOut, rejected
}
