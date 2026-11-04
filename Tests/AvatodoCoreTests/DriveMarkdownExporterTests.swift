import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AvatodoCore

private actor DriveFixture: DriveTransport {
    enum Step: Sendable { case reply(Int, String), failed }
    var steps: [Step]
    var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw DriveExportError.invalidResponse }
        switch steps.removeFirst() {
        case .failed: throw URLError(.timedOut)
        case let .reply(status, body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
private let folders = #"{"files":[{"id":"folder_1","mimeType":"application/vnd.google-apps.folder"}]}"#
private let emptyFiles = #"{"files":[]}"#
private func driveNote() -> Note {
    Note(id: UUID(), kind: .checklist, title: "Grocery / run", body: "For tonight", isComplete: false,
         items: [ChecklistItem(text: "Oat milk"), ChecklistItem(text: "Eggs", isComplete: true)], revision: 2)
}
private func driveState() -> (URL, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("avatodo-drive-fixture-" + UUID().uuidString)
    return (folder.appendingPathComponent("state.json"), folder)
}

@Test func driveMarkdownIsPortableAndContainsOnlyTheNote() throws {
    let note = driveNote(), text = NoteMarkdown.text(note)
    #expect(text.contains("avatodo_id: " + note.id.uuidString))
    #expect(text.contains("revision: 2"))
    #expect(text.contains("- [ ] Oat milk\n- [x] Eggs"))
    #expect(text.contains("For tonight"))
    #expect(!NoteMarkdown.filename(note).contains("/"))
    #expect(NoteMarkdown.filename(note).hasSuffix(".md"))
}

@Test func driveCreatesUserOwnedFolderAndMarkdownWithoutSharingPermissions() async throws {
    let (url, folder) = driveState(); defer { try? FileManager.default.removeItem(at: folder) }
    let fixture = DriveFixture([.reply(200, emptyFiles), .reply(200, #"{"ids":["folder_new"]}"#),
        .reply(200, #"{"id":"folder_new"}"#), .reply(200, emptyFiles),
        .reply(200, #"{"ids":["copy_new"]}"#), .reply(200, #"{"id":"copy_new"}"#)])
    let note = driveNote()
    let summary = try await DriveMarkdownExporter(stateURL: url, transport: fixture).upload(notes: [note], accountID: "account_A", token: { "fixture-token" })
    #expect(summary.folderID == "folder_new" && summary.uploadedCount == 1)
    let requests = await fixture.requests
    #expect(requests.count == 6)
    #expect(requests.allSatisfy { $0.url?.host == "www.googleapis.com" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
    #expect(!requests.contains { $0.url!.path.contains("permissions") })
    let body = String(data: requests.last!.httpBody!, encoding: .utf8)!
    #expect(body.contains("text/markdown") && body.contains("- [x] Eggs"))
    #expect(body.contains("copy_new") && body.contains("folder_new"))
    let persisted = try String(contentsOf: url, encoding: .utf8)
    #expect(!persisted.contains("fixture-token") && !persisted.contains("Oat milk"))
}

@Test func driveRetryUsesReservedIDAfterLostCreateResponse() async throws {
    let (url, folder) = driveState(); defer { try? FileManager.default.removeItem(at: folder) }
    let note = driveNote()
    let first = DriveFixture([.reply(200, folders), .reply(200, emptyFiles),
        .reply(200, #"{"ids":["reserved_copy"]}"#), .failed])
    await #expect(throws: URLError.self) {
        try await DriveMarkdownExporter(stateURL: url, transport: first).upload(notes: [note], accountID: "account_A", token: { "fixture-token" })
    }
    let saved = "{\"id\":\"reserved_copy\",\"appProperties\":{\"avatodo_note_id\":\"\(note.id.uuidString)\"},\"parents\":[\"folder_1\"],\"trashed\":false}"
    let retry = DriveFixture([.reply(200, folders), .reply(200, emptyFiles), .reply(409, "{}"),
        .reply(200, saved), .reply(200, #"{"id":"reserved_copy"}"#)])
    let result = try await DriveMarkdownExporter(stateURL: url, transport: retry).upload(notes: [note], accountID: "account_A", token: { "fixture-token" })
    #expect(result.uploadedCount == 1)
    let requests = await retry.requests
    #expect(!requests.contains { $0.url!.path.contains("generateIds") })
    #expect(String(data: requests[2].httpBody!, encoding: .utf8)?.contains("reserved_copy") == true)
    #expect(requests.last?.httpMethod == "PATCH")
    #expect(requests.last?.url?.path.hasSuffix("reserved_copy") == true)
}

@Test func driveSkipsAnUnchangedRevisionAndDoesNotImportCloudEdits() async throws {
    let (url, folder) = driveState(); defer { try? FileManager.default.removeItem(at: folder) }
    let note = driveNote()
    let files = "{\"files\":[{\"id\":\"copy_1\",\"mimeType\":\"text/markdown\",\"appProperties\":{\"avatodo_note_id\":\"\(note.id.uuidString)\",\"avatodo_revision\":\"2\",\"avatodo_format\":\"1\"}}]}"
    let fixture = DriveFixture([.reply(200, folders), .reply(200, files)])
    let result = try await DriveMarkdownExporter(stateURL: url, transport: fixture).upload(notes: [note], accountID: "account_A", token: { "fixture-token" })
    #expect(result.uploadedCount == 0)
    #expect(await fixture.requests.count == 2)
    #expect(await fixture.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.query?.contains("alt=media") != true })
}

@Test func driveAccountSwitchNeverReusesAnotherAccountsReservedIDs() async throws {
    let (url, folder) = driveState(); defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let note = driveNote()
    let old = "{\"version\":1,\"accountID\":\"account_A\",\"folderID\":\"old_folder\",\"fileIDs\":{\"\(note.id.uuidString)\":\"old_copy\"}}"
    try Data(old.utf8).write(to: url)
    let fixture = DriveFixture([.reply(200, folders), .reply(200, emptyFiles),
        .reply(200, #"{"ids":["new_account_copy"]}"#), .reply(200, #"{"id":"new_account_copy"}"#)])
    _ = try await DriveMarkdownExporter(stateURL: url, transport: fixture).upload(notes: [note], accountID: "account_B", token: { "fixture-token-B" })
    let requests = await fixture.requests
    #expect(requests.contains { $0.url!.path.contains("generateIds") })
    #expect(!requests.contains { String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains("old_copy") == true })
}

@Test func driveRejectsCorruptStateAndDuplicateTargetsWithoutUploadingNotes() async throws {
    let (url, folder) = driveState(); defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("broken".utf8).write(to: url)
    let noRequests = DriveFixture([])
    await #expect(throws: DriveExportError.unreadableState) {
        try await DriveMarkdownExporter(stateURL: url, transport: noRequests).upload(notes: [], accountID: "account_A", token: { "fixture-token" })
    }
    #expect(await noRequests.requests.isEmpty)
    try FileManager.default.removeItem(at: url)
    let id = UUID().uuidString
    let duplicates = "{\"files\":[{\"id\":\"a\",\"appProperties\":{\"avatodo_note_id\":\"\(id)\"}},{\"id\":\"b\",\"appProperties\":{\"avatodo_note_id\":\"\(id)\"}}]}"
    let fixture = DriveFixture([.reply(200, folders), .reply(200, duplicates)])
    await #expect(throws: DriveExportError.duplicateNote) {
        try await DriveMarkdownExporter(stateURL: url, transport: fixture).upload(notes: [], accountID: "account_A", token: { "fixture-token" })
    }
    #expect(await fixture.requests.allSatisfy { $0.httpMethod == "GET" })
}

@Test func driveErrorsNeverExposeProviderContentOrCredentials() async throws {
    let (url, folder) = driveState(); defer { try? FileManager.default.removeItem(at: folder) }
    let fixture = DriveFixture([.reply(401, #"{"error":{"message":"private-provider-content"}}"#)])
    do {
        _ = try await DriveMarkdownExporter(stateURL: url, transport: fixture).upload(notes: [driveNote()], accountID: "account_A", token: { "fixture-token" })
        Issue.record("Authentication failure was ignored")
    } catch let error as DriveExportError {
        #expect(error == .http(401))
        #expect(!error.localizedDescription.contains("private-provider-content"))
        #expect(!error.localizedDescription.contains("fixture-token"))
    }
}
