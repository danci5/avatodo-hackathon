import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DriveExportError: Error, Equatable, Sendable, LocalizedError {
    case busy, invalidResponse, unreadableState, ambiguousFolder, duplicateNote, http(Int)
    public var errorDescription: String? {
        switch self {
        case .busy: "A Drive upload is already in progress."
        case .unreadableState: "The Drive upload settings couldn’t be opened. Your notes are unchanged."
        case .ambiguousFolder: "More than one Avatodo folder was found. Please check your Drive folders."
        case .duplicateNote: "Duplicate Avatodo copies were found in Drive. Please check the folder before uploading again."
        case .http(401): "Reconnect Google Drive to continue uploading copies."
        case .http(403): "Google Drive denied access. Check the connected account and permissions."
        case .http(429): "Google Drive is busy. Try uploading again shortly."
        case .http(let code): "Google Drive couldn’t finish the upload (HTTP \(code)). Your notes are safe on this iPhone."
        case .invalidResponse: "Google Drive returned an unreadable response. Your notes are unchanged."
        }
    }
}

public protocol DriveTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
private struct DriveURLTransport: DriveTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}

public struct DriveExportSummary: Sendable {
    public let folderID: String
    public let noteCount: Int
    public let uploadedCount: Int
}

public enum NoteMarkdown {
    public static func text(_ note: Note) -> String {
        var text = "---\navatodo_id: \(note.id.uuidString)\nrevision: \(note.revision)\nkind: \(note.kind.rawValue)\n---\n\n# \(note.title.replacingOccurrences(of: "\n", with: " "))\n"
        if !note.body.isEmpty { text += "\n" + note.body + "\n" }
        if note.kind == .task { text += "\n- [\(note.isComplete ? "x" : " ")] \(note.title)\n" }
        if !note.items.isEmpty {
            text += "\n" + note.items.map { "- [\($0.isComplete ? "x" : " ")] \($0.text.replacingOccurrences(of: "\n", with: " "))" }.joined(separator: "\n") + "\n"
        }
        return text
    }
    public static func filename(_ note: Note) -> String {
        let cleaned = note.title.map { char in char.isNewline || char == "/" || char == "\\" ? Character(" ") : char }
        let title = String(String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        return (title.isEmpty ? "Note" : title) + " (" + note.id.uuidString.prefix(8) + ").md"
    }
}

/// Outbound copies only. Notes, conversation, credentials and edit receipts stay
/// under separate ownership. A reserved Drive ID is saved before every create,
/// so retrying an upload whose response was lost cannot create a second file.
public actor DriveMarkdownExporter {
    private struct Index: Codable {
        var version = 1
        var accountID: String
        var folderID: String?
        var fileIDs: [String: String] = [:]
    }
    private struct File: Decodable {
        let id: String
        var mimeType: String?
        var appProperties: [String: String]?
    }
    private struct Files: Decodable { let files: [File]; var nextPageToken: String? }
    private let stateURL: URL
    private let transport: any DriveTransport
    private var running = false
    public init(stateURL: URL) { self.stateURL = stateURL; transport = DriveURLTransport() }
    public init(stateURL: URL, transport: any DriveTransport) { self.stateURL = stateURL; self.transport = transport }

    public func upload(notes: [Note], accountID: String,
                       token: @escaping @Sendable () async throws -> String) async throws -> DriveExportSummary {
        guard !running else { throw DriveExportError.busy }
        running = true; defer { running = false }
        var index = try load(accountID: accountID)
        let fields = "nextPageToken,files(id,mimeType,appProperties)"
        let folders = try await list(query: "trashed = false and mimeType = 'application/vnd.google-apps.folder' and appProperties has { key='avatodo_role' and value='notes_folder_v1' }", fields: fields, token: token)
        guard folders.count <= 1 else { throw DriveExportError.ambiguousFolder }
        let folderID: String
        if let existing = folders.first {
            guard validID(existing.id) else { throw DriveExportError.invalidResponse }
            folderID = existing.id; index.folderID = folderID; try save(index)
        } else {
            folderID = try await reserveID(existing: index.folderID, token: token)
            index.folderID = folderID; try save(index)
            let metadata: JSONValue = .object(["id": .string(folderID), "name": .string("Avatodo"),
                "mimeType": .string("application/vnd.google-apps.folder"),
                "appProperties": .object(["avatodo_role": .string("notes_folder_v1")])])
            do { _ = try await request(path: "drive/v3/files", method: "POST", payload: metadata, token: token) }
            catch DriveExportError.http(409) {
                let existing = try await request(path: "drive/v3/files/" + folderID,
                    query: ["fields": "id,mimeType,appProperties,trashed"], token: token)
                guard existing["appProperties"]["avatodo_role"].string == "notes_folder_v1",
                      existing["mimeType"].string == "application/vnd.google-apps.folder", existing["trashed"].bool != true
                else { throw DriveExportError.ambiguousFolder }
            }
        }
        let remote = try await list(query: "trashed = false and '\(folderID)' in parents", fields: fields, token: token)
        var byNote: [String: File] = [:]
        for file in remote {
            guard let noteID = file.appProperties?["avatodo_note_id"], UUID(uuidString: noteID) != nil else { continue }
            guard byNote[noteID] == nil else { throw DriveExportError.duplicateNote }
            guard validID(file.id) else { throw DriveExportError.invalidResponse }
            byNote[noteID] = file
        }
        var uploaded = 0
        for note in notes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try Task.checkCancellation()
            let localID = note.id.uuidString
            let existing = byNote[localID]
            if existing?.appProperties?["avatodo_revision"] == String(note.revision),
               existing?.appProperties?["avatodo_format"] == "1", existing?.mimeType == "text/markdown" { continue }
            let fileID = try await reserveID(existing: existing?.id ?? index.fileIDs[localID], token: token)
            index.fileIDs[localID] = fileID; try save(index)
            var metadata: [String: JSONValue] = ["name": .string(NoteMarkdown.filename(note)), "mimeType": .string("text/markdown"),
                "appProperties": .object(["avatodo_note_id": .string(localID),
                    "avatodo_revision": .string(String(note.revision)), "avatodo_format": .string("1")])]
            if existing == nil { metadata["id"] = .string(fileID); metadata["parents"] = .array([.string(folderID)]) }
            do { try await uploadFile(id: existing?.id, metadata: .object(metadata), markdown: NoteMarkdown.text(note), token: token) }
            catch DriveExportError.http(409) {
                // The prior create may have committed before its reply was lost.
                let saved = try await request(path: "drive/v3/files/" + fileID,
                    query: ["fields": "id,appProperties,parents,trashed"], token: token)
                guard saved["appProperties"]["avatodo_note_id"].string == localID,
                      saved["parents"].array?.contains(.string(folderID)) == true,
                      saved["trashed"].bool != true else { throw DriveExportError.duplicateNote }
                metadata.removeValue(forKey: "id"); metadata.removeValue(forKey: "parents")
                try await uploadFile(id: fileID, metadata: .object(metadata), markdown: NoteMarkdown.text(note), token: token)
            }
            uploaded += 1
        }
        return DriveExportSummary(folderID: folderID, noteCount: notes.count, uploadedCount: uploaded)
    }

    private func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 200 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    private func load(accountID: String) throws -> Index {
        guard !accountID.isEmpty, accountID.count <= 300 else { throw DriveExportError.unreadableState }
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return Index(accountID: accountID) }
        guard let data = try? Data(contentsOf: stateURL), data.count <= 1_000_000,
              let index = try? JSONDecoder().decode(Index.self, from: data), index.version == 1,
              index.folderID.map(validID) ?? true,
              index.fileIDs.allSatisfy({ UUID(uuidString: $0.key) != nil && validID($0.value) }) else {
            throw DriveExportError.unreadableState
        }
        return index.accountID == accountID ? index : Index(accountID: accountID)
    }
    private func save(_ index: Index) throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(index).write(to: stateURL, options: .atomic)
    }
    private func reserveID(existing: String?, token: @escaping @Sendable () async throws -> String) async throws -> String {
        if let existing, validID(existing) { return existing }
        let value = try await request(path: "drive/v3/files/generateIds", query: ["count": "1", "space": "drive", "type": "files"], token: token)
        guard let id = value["ids"].array?.first?.string, validID(id) else { throw DriveExportError.invalidResponse }
        return id
    }
    private func list(query: String, fields: String, token: @escaping @Sendable () async throws -> String) async throws -> [File] {
        var files: [File] = [], page: String?
        for _ in 0..<20 {
            var parameters = ["q": query, "fields": fields, "pageSize": "1000", "spaces": "drive"]
            if let page { parameters["pageToken"] = page }
            let value = try await request(path: "drive/v3/files", query: parameters, token: token)
            let batch = try JSONDecoder().decode(Files.self, from: JSONEncoder().encode(value))
            files += batch.files; page = batch.nextPageToken
            if page == nil { return files }
        }
        throw DriveExportError.invalidResponse
    }
    private func uploadFile(id: String?, metadata: JSONValue, markdown: String,
                            token: @escaping @Sendable () async throws -> String) async throws {
        let boundary = "avatodo_" + UUID().uuidString
        var data = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        data.append(try JSONEncoder().encode(metadata))
        data.append(Data("\r\n--\(boundary)\r\nContent-Type: text/markdown; charset=UTF-8\r\n\r\n\(markdown)\r\n--\(boundary)--\r\n".utf8))
        _ = try await request(path: "upload/drive/v3/files" + (id.map { "/" + $0 } ?? ""),
            method: id == nil ? "POST" : "PATCH", query: ["uploadType": "multipart", "fields": "id"],
            body: data, contentType: "multipart/related; boundary=" + boundary, token: token)
    }
    private func request(path: String, method: String = "GET", query: [String: String] = [:],
                         payload: JSONValue? = nil, body: Data? = nil, contentType: String = "application/json",
                         token: @escaping @Sendable () async throws -> String) async throws -> JSONValue {
        try Task.checkCancellation()
        let bearer = try await token()
        guard !bearer.isEmpty, !bearer.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw DriveExportError.http(401) }
        var components = URLComponents(string: "https://www.googleapis.com/" + path)!
        if !query.isEmpty { components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = try body ?? payload.map { try JSONEncoder().encode($0) }
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw DriveExportError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw DriveExportError.http(http.statusCode) }
        guard data.count <= 4_000_000, let result = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw DriveExportError.invalidResponse }
        return result
    }
}
