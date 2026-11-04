import Foundation

@main enum ReplyAudioChecks {
    static func main() throws {
        let request = UUID(), transfer = UUID()
        let data = Data((0..<70_001).map { UInt8($0 % 251) })
        let manifest = ReplyAudioManifest(id: transfer, requestID: request, sha256: ReplyAudioAssembler.digest(data), totalBytes: data.count, duration: 2)
        let count = (data.count + ReplyAudioChunk.payloadBytes - 1) / ReplyAudioChunk.payloadBytes
        let chunks = (0..<count).map { index in
            let offset = index * ReplyAudioChunk.payloadBytes
            return ReplyAudioChunk(manifest: manifest, index: index, count: count,
                bytes: data.subdata(in: offset..<min(offset + ReplyAudioChunk.payloadBytes, data.count)))
        }
        var assembler = ReplyAudioAssembler(); assembler.begin(request)
        for index in [2, 0, 0, 1] { let value = try assembler.accept(chunks[index]); precondition(value == nil) }
        precondition(assembler.bufferedBytes == data.count)
        let completed = try assembler.select(transfer, requestID: request)
        precondition(completed?.data == data && assembler.bufferedBytes == 0)
        let duplicate = try assembler.accept(chunks[0]); precondition(duplicate == nil)
        print("PASS reordered/duplicate chunks wait for selection and produce exact audio only once")

        assembler.begin(request); _ = try assembler.select(transfer, requestID: request)
        _ = try assembler.accept(chunks[0]); assembler.close()
        for chunk in chunks { let value = try assembler.accept(chunk); precondition(value == nil) }
        precondition(assembler.bufferedBytes == 0)
        assembler.begin(UUID())
        let old = try assembler.accept(chunks[0]); precondition(old == nil)
        print("PASS Stop/fallback closes pending audio; a newer turn rejects all older audio")

        var corrupt = chunks[0].bytes; corrupt[0] ^= 1
        let changed = ReplyAudioChunk(manifest: manifest, index: 0, count: count, bytes: corrupt)
        assembler.begin(request); _ = try assembler.select(transfer, requestID: request)
        _ = try assembler.accept(changed); _ = try assembler.accept(chunks[1])
        do { _ = try assembler.accept(chunks[2]); preconditionFailure("Corrupt audio accepted") }
        catch ReplyAudioFailure.invalid { }
        precondition(assembler.bufferedBytes == 0)
        print("PASS corrupt payload hash fails closed without retaining audio")

        assembler.begin(request); _ = try assembler.accept(chunks[0])
        do { _ = try assembler.accept(changed); preconditionFailure("Conflicting duplicate accepted") }
        catch ReplyAudioFailure.invalid { }
        let huge = ReplyAudioManifest(id: UUID(), requestID: request, sha256: manifest.sha256, totalBytes: 2_000_001, duration: 2)
        assembler.begin(request)
        do { _ = try assembler.accept(ReplyAudioChunk(manifest: huge, index: 0, count: 84, bytes: Data())); preconditionFailure("Oversized clip accepted") }
        catch ReplyAudioFailure.invalid { }
        print("PASS conflicting duplicates and oversized clips are rejected")

        for chunk in chunks {
            let encoded = try JSONEncoder().encode(chunk)
            precondition(encoded.count <= 48_000)
        }
        var state = CompanionViewState()
        state.watchVoiceMode = .iPhone; state.replyAudioExpected = true; state.replyAudioID = transfer
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CompanionViewState.self, from: encoded)
        precondition(decoded.watchVoiceMode == .iPhone && decoded.replyAudioID == transfer)
        print("PASS audio messages fit foreground bounds; optional voice mode and clip selection survive wire encoding")
    }
}
