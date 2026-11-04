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
    func transferCharacter(url: URL, manifest: CharacterManifest) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(manifest) else { return }
        guard !session.outstandingFileTransfers.contains(where: { ($0.file.metadata?["manifest"] as? Data) == data }) else { return }
        session.transferFile(url, metadata: ["manifest": data])
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateReachability(session.isReachable)
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { updateReachability(session.isReachable) }
    nonisolated private func updateReachability(_ value: Bool) {
        Task { @MainActor [weak self] in
            self?.reachable = value; self?.connectivityChanged?(value)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String, let payload = message["payload"] as? Data,
              payload.count <= 300_000 else { return }
        // Prefix the small wire envelope so the callback only crosses isolation with Data.
        let envelope = WireEnvelope(type: type, payload: payload)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        Task { @MainActor [weak self] in self?.receive?(data) }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let manifest = file.metadata?["manifest"] as? Data, manifest.count <= 16_384,
              let size = try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4_000_000, let image = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor [weak self] in self?.receiveFile?(image, manifest) }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
struct WireEnvelope: Codable, Sendable { let type: String; let payload: Data }
