import Foundation
import CryptoKit

@main enum CharacterTransferChecks {
    static func main() throws {
        let generated = Date(timeIntervalSinceReferenceDate: 1000)
        let bytes = Data((0..<105_001).map { UInt8($0 % 251) })
        let manifest = CharacterManifest(id: UUID(), name: "Ava", sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            generatedAt: generated, sourceModel: "fixture")
        let run = UUID()
        let parts = chunks(bytes, manifest: manifest, run: run)
        var assembler = CharacterChunkAssembler()
        _ = assembler.select(manifest.id, at: generated.addingTimeInterval(1))
        var result: CompletedCharacterTransfer?
        for index in [4, 2, 2, 0, 3, 1] {
            let next = try assembler.accept(parts[index])
            if let next { result = next }
            precondition(assembler.bufferedBytes <= bytes.count)
        }
        precondition(result?.image == bytes && result?.manifest == manifest)
        let retired = try assembler.accept(parts[0]); precondition(retired == nil, "Retired duplicates cannot reinstall")
        print("PASS reordered chunks, harmless duplicates, exact bytes and final hash")

        var pending = CharacterChunkAssembler()
        for part in parts { let value = try pending.accept(part); precondition(value == nil) }
        precondition(pending.bufferedBytes == bytes.count)
        precondition(pending.select(manifest.id, at: generated.addingTimeInterval(1))?.image == bytes)
        print("PASS image waits in bounded RAM until authoritative selection")

        var reset = CharacterChunkAssembler()
        _ = reset.select(manifest.id, at: generated)
        _ = try reset.accept(parts[0])
        _ = reset.select(nil, at: generated.addingTimeInterval(2))
        precondition(reset.bufferedBytes == 0)
        for part in parts { let value = try reset.accept(part); precondition(value == nil) }
        precondition(reset.select(manifest.id, at: generated.addingTimeInterval(3)) == nil)
        print("PASS default reset discards partial and late stale transfers")

        var future = CharacterChunkAssembler()
        _ = future.select(nil, at: generated.addingTimeInterval(-1))
        for part in parts { let value = try future.accept(part); precondition(value == nil) }
        precondition(future.select(manifest.id, at: generated.addingTimeInterval(1))?.image == bytes)
        print("PASS newer creation may precede its state message without installing early")

        var corrupted = parts
        var changed = parts[0].bytes; changed[0] ^= 1
        corrupted[0] = CharacterChunk(transferID: run, manifest: manifest, index: 0, count: parts.count, totalBytes: bytes.count, bytes: changed)
        var bad = CharacterChunkAssembler(); _ = bad.select(manifest.id, at: generated)
        do { for part in corrupted { _ = try bad.accept(part) }; preconditionFailure("Hash mismatch accepted") }
        catch CharacterTransferError.hashMismatch {}
        precondition(bad.bufferedBytes == 0)
        print("PASS corrupt final hash rejected without keeping pending data")

        var conflict = CharacterChunkAssembler(); _ = conflict.select(manifest.id, at: generated)
        _ = try conflict.accept(parts[0])
        do { _ = try conflict.accept(corrupted[0]); preconditionFailure("Conflicting duplicate accepted") }
        catch CharacterTransferError.conflictingChunk {}
        let invalid = CharacterChunk(transferID: UUID(), manifest: manifest, index: 0, count: 1, totalBytes: 4_000_001, bytes: Data())
        do { _ = try conflict.accept(invalid); preconditionFailure("Oversize image accepted") }
        catch CharacterTransferError.invalidChunk {}
        print("PASS conflicting duplicates and oversized image metadata rejected")
    }
    static func chunks(_ data: Data, manifest: CharacterManifest, run: UUID) -> [CharacterChunk] {
        let count = (data.count + CharacterChunk.payloadBytes - 1) / CharacterChunk.payloadBytes
        return (0..<count).map { index in
            let start = index * CharacterChunk.payloadBytes
            return CharacterChunk(transferID: run, manifest: manifest, index: index, count: count, totalBytes: data.count,
                bytes: data.subdata(in: start..<min(start + CharacterChunk.payloadBytes, data.count)))
        }
    }
}
