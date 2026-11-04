import Foundation
import Observation
import UIKit
@preconcurrency import GoogleSignIn
import AvatodoCore

/// Google owns authentication; the iPhone owns uploads. No Avatodo account,
/// server, client secret or Google credential ever crosses the Watch link.
@MainActor @Observable final class GoogleDriveSync {
    static let scope = "https://www.googleapis.com/auth/drive.file"
    private(set) var accountEmail: String?
    private(set) var connected = false
    private(set) var connecting = false
    private(set) var uploading = false
    private(set) var message: String?
    private(set) var folderID: String?
    private var accountID: String?
    private var epoch = UUID()
    private var pending: [Note]?
    private var uploadTask: Task<Void, Never>?
    private var restored = false
    private let exporter: DriveMarkdownExporter
    var configured: Bool { Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String != nil }
    var folderURL: URL? { folderID.flatMap { URL(string: "https://drive.google.com/drive/folders/" + $0) } }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DriveExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        exporter = DriveMarkdownExporter(stateURL: folder.appendingPathComponent("index.json"))
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }
    func handle(_ url: URL) { _ = GIDSignIn.sharedInstance.handle(url) }
    func restore(notes: [Note]) async {
        guard !restored else { changed(notes); return }
        restored = true
        guard configured, UserDefaults.standard.bool(forKey: "driveCopiesConnected") else { return }
        let generation = epoch
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            guard epoch == generation else { return }
            try accept(user)
            changed(notes)
        } catch {
            guard epoch == generation else { return }
            message = "Reconnect Google Drive to continue uploading copies."
        }
    }
    func connect(notes: [Note]) async {
        guard configured, !connecting else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            message = "Open Avatodo and try connecting again."; return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        connecting = true; message = nil
        let generation = epoch
        defer { connecting = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [Self.scope])
            guard epoch == generation else { return }
            try accept(result.user)
            UserDefaults.standard.set(true, forKey: "driveCopiesConnected")
            changed(notes)
        } catch {
            guard epoch == generation else { return }
            let ns = error as NSError
            if ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue { return }
            message = "Google sign-in couldn’t finish. Please try again."
        }
    }
    private func accept(_ user: GIDGoogleUser) throws {
        guard let id = user.userID, (user.grantedScopes ?? []).contains(Self.scope) else { throw DriveExportError.http(403) }
        if accountID != id { folderID = nil }
        accountID = id; accountEmail = user.profile?.email; connected = true
    }
    func disconnect() {
        epoch = UUID(); uploadTask?.cancel(); uploadTask = nil; pending = nil
        accountID = nil; accountEmail = nil; connected = false; connecting = false; uploading = false; folderID = nil
        UserDefaults.standard.set(false, forKey: "driveCopiesConnected")
        GIDSignIn.sharedInstance.signOut()
        message = "Disconnected on this iPhone. Existing copies remain in Google Drive."
    }
    func changed(_ notes: [Note]) {
        guard connected, let accountID else { return }
        pending = notes
        guard uploadTask == nil else { return }
        let generation = epoch
        uploadTask = Task { [weak self] in
            guard let self else { return }
            defer { if epoch == generation { uploading = false; uploadTask = nil } }
            // Coalesce a quick series of local edits; do not delay the agent or audio.
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled, epoch == generation, let notes = pending {
                pending = nil; uploading = true; message = "Uploading Markdown copies…"
                do {
                    let result = try await exporter.upload(notes: notes, accountID: accountID) { [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await self.token(for: accountID, generation: generation)
                    }
                    guard epoch == generation else { return }
                    folderID = result.folderID
                    message = "\(result.noteCount) \(result.noteCount == 1 ? "note" : "notes") up to date in Drive."
                } catch is CancellationError { return }
                catch {
                    guard epoch == generation else { return }
                    message = (error as? DriveExportError)?.localizedDescription ?? "Drive couldn’t finish. Your notes are safe on this iPhone. Try Upload now."
                    return
                }
            }
        }
    }
    private func token(for account: String, generation: UUID) async throws -> String {
        guard connected, epoch == generation, accountID == account,
              let user = GIDSignIn.sharedInstance.currentUser, user.userID == account else { throw CancellationError() }
        let refreshed = try await user.refreshTokensIfNeeded()
        guard connected, epoch == generation, accountID == account, refreshed.userID == account,
              (refreshed.grantedScopes ?? []).contains(Self.scope) else { throw CancellationError() }
        return refreshed.accessToken.tokenString
    }
}
