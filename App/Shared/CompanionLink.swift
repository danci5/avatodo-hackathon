import Foundation
@preconcurrency import WatchConnectivity

/// Only live commands/state/audio cross this link. Credentials and chat archives never do.
@MainActor final class CompanionLink: NSObject, WCSessionDelegate {
    var receive: (@MainActor (Data) -> Void)?
    var receiveFile: (@MainActor (Data, Data) -> Void)?
    var connectivityChanged: (@MainActor (Bool) -> Void)?
    var deliveryError: (@MainActor () -> Void)?
    private(set) var reachable = false
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var foregroundCharacter: UUID?
    private var foregroundRun: UUID?
    private var foregroundTask: Task<Void, Never>?
    private var foregroundAttempts = 0
    private var foregroundCompleted = false

    override init() {
        super.init(); session?.delegate = self; session?.activate()
    }
    func send<T: Encodable>(_ value: T, type: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        send(data, type: type)
    }
    private func send(_ data: Data, type: String) {
        guard let session, session.activationState == .activated, session.isReachable else { deliveryError?(); return }
        session.sendMessage(["type": type, "payload": data], replyHandler: nil) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.deliveryError?() }
        }
    }
    func sendState(_ state: CompanionViewState) { send(state, type: "state") }

    /// Keep the system background transfer, and also send bounded acknowledged
    /// chunks while both apps are reachable. The latter avoids waiting for the
    /// background file scheduler during companion creation and foreground use.
    func transferCharacter(url: URL, manifest: CharacterManifest, retryForeground: Bool = false) {
        guard let session, session.activationState == .activated,
              let metadata = try? JSONEncoder().encode(manifest) else { return }
        if foregroundCharacter != manifest.id {
            cancelCharacterTransfers()
            foregroundCharacter = manifest.id
        }
        let hasQueuedFile = session.outstandingFileTransfers.contains { transfer in
            guard let data = transfer.file.metadata?["manifest"] as? Data,
                  let queued = try? JSONDecoder().decode(CharacterManifest.self, from: data) else { return false }
            return queued.id == manifest.id && queued.sha256 == manifest.sha256
        }
        if !hasQueuedFile { session.transferFile(url, metadata: ["manifest": metadata]) }
        guard session.isReachable, foregroundTask == nil, foregroundAttempts < 3,
              !foregroundCompleted || retryForeground,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= CharacterChunk.maximumImageBytes,
              let image = try? Data(contentsOf: url), image.count == size else { return }
        foregroundAttempts += 1
        let run = UUID(); foregroundRun = run
        foregroundTask = Task { [weak self] in
            guard let self else { return }
            defer { if foregroundRun == run { foregroundTask = nil } }
            do {
                let count = (image.count + CharacterChunk.payloadBytes - 1) / CharacterChunk.payloadBytes
                let started = Date()
                for index in 0..<count {
                    try Task.checkCancellation()
                    guard foregroundRun == run, foregroundCharacter == manifest.id else { throw CancellationError() }
                    guard Date().timeIntervalSince(started) < 90 else { throw CharacterTransferError.timedOut }
                    let start = index * CharacterChunk.payloadBytes
                    let chunk = CharacterChunk(transferID: run, manifest: manifest, index: index, count: count,
                        totalBytes: image.count, bytes: image.subdata(in: start..<min(start + CharacterChunk.payloadBytes, image.count)))
                    try await sendAcknowledged(try JSONEncoder().encode(chunk), type: "characterChunk", timeout: min(8, 90 - Date().timeIntervalSince(started)))
                }
                if foregroundRun == run { foregroundCompleted = true }
            } catch {
                // The valid cached artwork stays visible. A later explicit image
                // request may retry, at most three foreground attempts per selection.
            }
        }
    }
    func cancelCharacterTransfers() {
        foregroundRun = nil; foregroundTask?.cancel(); foregroundTask = nil
        foregroundCharacter = nil; foregroundAttempts = 0; foregroundCompleted = false
        for transfer in session?.outstandingFileTransfers ?? [] where transfer.file.metadata?["manifest"] is Data {
            transfer.cancel()
        }
    }
    private func sendAcknowledged(_ data: Data, type: String, timeout: TimeInterval) async throws {
        guard data.count <= 48_000, let session, session.activationState == .activated, session.isReachable else {
            throw CharacterTransferError.unavailable
        }
        let acknowledgement = WireAcknowledgement()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                acknowledgement.install(continuation)
                session.sendMessage(["type": type, "payload": data], replyHandler: { @Sendable reply in
                    let accepted = reply["accepted"] as? Bool == true
                    Task { @MainActor in acknowledgement.finish(accepted ? .success(()) : .failure(CharacterTransferError.rejected)) }
                }, errorHandler: { @Sendable _ in
                    Task { @MainActor in acknowledgement.finish(.failure(CharacterTransferError.unavailable)) }
                })
                acknowledgement.timeout = Task {
                    try? await Task.sleep(for: .seconds(max(0.1, timeout)))
                    guard !Task.isCancelled else { return }
                    acknowledgement.finish(.failure(CharacterTransferError.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor in acknowledgement.finish(.failure(CancellationError())) }
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateReachability(session.isReachable)
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { updateReachability(session.isReachable) }
    nonisolated private func updateReachability(_ value: Bool) {
        Task { @MainActor [weak self] in
            self?.reachable = value
            if !value { self?.foregroundTask?.cancel() }
            self?.connectivityChanged?(value)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = Self.envelope(message) else { return }
        Task { @MainActor [weak self] in self?.receive?(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = Self.envelope(message) else { replyHandler(["accepted": false]); return }
        // Acknowledge receipt immediately. Decoding/assembly/installing happen on
        // MainActor afterwards, never blocking the WC reply deadline.
        replyHandler(["accepted": true])
        Task { @MainActor [weak self] in self?.receive?(data) }
    }
    private nonisolated static func envelope(_ message: [String: Any]) -> Data? {
        guard let type = message["type"] as? String, let payload = message["payload"] as? Data,
              payload.count <= (type == "characterChunk" ? 48_000 : 300_000) else { return nil }
        return try? JSONEncoder().encode(WireEnvelope(type: type, payload: payload))
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let manifest = file.metadata?["manifest"] as? Data, manifest.count <= 16_384,
              let size = try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= CharacterChunk.maximumImageBytes, let image = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor [weak self] in self?.receiveFile?(image, manifest) }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

@MainActor private final class WireAcknowledgement {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?
    var timeout: Task<Void, Never>?
    func install(_ continuation: CheckedContinuation<Void, any Error>) {
        if let result { continuation.resume(with: result) }
        else { self.continuation = continuation }
    }
    func finish(_ result: Result<Void, any Error>) {
        guard self.result == nil else { return }
        self.result = result; timeout?.cancel(); continuation?.resume(with: result); continuation = nil
    }
}
struct WireEnvelope: Codable, Sendable { let type: String; let payload: Data }
