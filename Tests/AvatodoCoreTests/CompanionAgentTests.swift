import Foundation
import Testing
@testable import AvatodoCore

private actor ScriptedLanguageModel: LanguageModel {
    var responses: [JSONValue]
    var invocations: [[JSONValue]] = []
    init(_ responses: [JSONValue]) { self.responses = responses }
    func complete(messages: [JSONValue], tools: [JSONValue], key: String) async throws -> JSONValue {
        invocations.append(messages)
        guard !responses.isEmpty else { throw MetaError.emptyReply }
        return responses.removeFirst()
    }
    var count: Int { invocations.count }
}

private func response(_ text: String) -> JSONValue {
    .object(["choices": .array([.object(["message": .object(["role": .string("assistant"), "content": .string(text)])])])])
}
private func toolResponse(_ name: String, _ arguments: JSONValue, id: String = UUID().uuidString) throws -> JSONValue {
    .object(["choices": .array([.object(["message": .object([
        "role": .string("assistant"), "content": .null,
        "tool_calls": .array([.object(["id": .string(id), "type": .string("function"), "function": .object([
            "name": .string(name), "arguments": .string(try arguments.jsonString())])])])
    ])])])])
}
private func testStore() throws -> (LocalTaskStore, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("avatodo-agent-" + UUID().uuidString)
    return (try LocalTaskStore(persistence: JSONFilePersistence(url: folder.appendingPathComponent("notes.json"))), folder)
}
private func create(_ title: String = "Grocery run") -> MutationRequest {
    MutationRequest(action: .create(id: UUID(), kind: .checklist, title: title, body: "", items: [ChecklistItem(text: "Milk")]))
}

@Test func currentCompanionNameIsSentEachTurnAndOverridesEarlierIdentity() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let model = ScriptedLanguageModel([response("I'm Nikola."), response("I'm Ava.")])
    let agent = CompanionAgent(store: store, model: model)
    _ = try await agent.respond(to: "What is your name?", key: "fixture", companionName: "  Nikola  ")
    _ = try await agent.respond(to: "And now?", key: "fixture", companionName: "Ava")
    let calls = await model.invocations
    let context1 = calls[0][1]["content"].string ?? ""
    let context2 = calls[1][1]["content"].string ?? ""
    #expect(context1.contains("Nikola"))
    #expect(context2.contains("Ava"))
    #expect(!context2.contains("Nikola"))
    #expect(calls[1].contains { $0["content"].string == "I'm Nikola." })
    #expect(calls[1][0]["content"].string?.contains("even if an earlier turn mentioned a different companion") == true)
    #expect(await store.notes().isEmpty)
}

@Test func identityIsBoundedAndPartOfRetryIdentity() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let model = ScriptedLanguageModel([response("Hello")])
    let agent = CompanionAgent(store: store, model: model)
    let id = UUID()
    _ = try await agent.respond(to: "Hello", requestID: id, key: "fixture", companionName: "  ")
    await #expect(throws: TaskStoreError.reusedRequestID) {
        try await agent.respond(to: "Hello", requestID: id, key: "fixture", companionName: "Nikola")
    }
    let calls = await model.invocations
    #expect(calls[0][1]["content"].string?.contains("Ava") == true)
    #expect(await model.count == 1)
}

@Test func normalRepliesNeverCreateNotesAndFreshClearsContext() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let model = ScriptedLanguageModel((0..<8).map { _ in response("Doing well. How are you?") })
    let agent = CompanionAgent(store: store, model: model)
    for _ in 0..<8 { _ = try await agent.respond(to: "How are you?", key: "fixture") }
    #expect(await store.notes().isEmpty)
    #expect(await agent.recentTurnCount == 6)
    #expect(await agent.startFresh())
    #expect(await agent.recentTurnCount == 0)
    #expect(await agent.activeNoteID == nil)
}

@Test func activeNoteSurvivesHistoryEvictionAndTwentyAdditions() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let saved = try await store.perform(create())
    var replies: [JSONValue] = []
    for index in 0..<20 {
        replies += [try toolResponse("add_checklist_items", .object([
            "note_id": .string(saved.noteID.uuidString), "expected_revision": .number(Double(index + 1)),
            "items": .array([.string("Item \(index + 1)")])])), response("Added it.")]
    }
    let agent = CompanionAgent(store: store, model: ScriptedLanguageModel(replies))
    for index in 0..<20 {
        _ = try await agent.respond(to: "Add item \(index + 1)", key: "fixture", scopedTo: index == 0 ? saved.noteID : nil)
    }
    #expect(try await store.note(id: saved.noteID).items.count == 21)
    #expect(await agent.recentTurnCount == 6)
    #expect(await agent.activeNoteID == saved.noteID)
}

@Test func scopedToolCannotWriteAnotherNoteOrCreateNewOne() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let a = try await store.perform(create("Same title")), b = try await store.perform(create("Same title"))
    let args: JSONValue = .object(["note_id": .string(b.noteID.uuidString), "expected_revision": .number(1), "text": .string("Wrong target")])
    await #expect(throws: AgentError.self) {
        try await NoteTools.execute(name: "append_to_note", arguments: args, mutationID: UUID(), scope: a.noteID, store: store)
    }
    #expect(try await store.note(id: b.noteID).body.isEmpty)
    await #expect(throws: AgentError.self) {
        try await NoteTools.execute(name: "create_note", arguments: .object(["kind": .string("note"), "title": .string("Oops"), "body": .string(""), "items": .array([])]), mutationID: UUID(), scope: a.noteID, store: store)
    }
    #expect(await store.notes().count == 2)
}

@Test func duplicateMutationInModelLoopDoesNotCreateTwoNotes() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let args: JSONValue = .object(["kind": .string("checklist"), "title": .string("Groceries"), "body": .string(""), "items": .array([.string("Eggs")])])
    let model = ScriptedLanguageModel([try toolResponse("create_note", args), try toolResponse("create_note", args), response("Saved.")])
    let agent = CompanionAgent(store: store, model: model)
    let requestID = UUID()
    let first = try await agent.respond(to: "Create my groceries", requestID: requestID, key: "fixture")
    #expect(first.receipts.count == 1)
    #expect(await store.notes().count == 1)
    let again = try await agent.respond(to: "Create my groceries", requestID: requestID, key: "fixture")
    #expect(again == first)
    #expect(await model.count == 3)
    // A process restart also recovers a committed command without contacting the model.
    let recoveredModel = ScriptedLanguageModel([])
    let restarted = CompanionAgent(store: try LocalTaskStore(persistence: JSONFilePersistence(url: folder.appendingPathComponent("notes.json"))), model: recoveredModel)
    let recovered = try await restarted.respond(to: "Create my groceries", requestID: requestID, key: "fixture")
    #expect(recovered.recoveredRequest)
    #expect(await recoveredModel.count == 0)
}

@Test func sessionExpiresOnlyAfterIdleAndKeepsNotes() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let note = try await store.perform(create())
    let agent = CompanionAgent(store: store, model: ScriptedLanguageModel([response("Here it is.")]))
    _ = try await agent.respond(to: "Tell me about this note", key: "fixture", scopedTo: note.noteID)
    let deadline = await agent.idleDeadline
    #expect(!(await agent.expireIfNeeded(now: deadline.addingTimeInterval(-1))))
    await agent.setPresentingReply(true)
    #expect(!(await agent.expireIfNeeded(now: deadline.addingTimeInterval(500))))
    await agent.setPresentingReply(false)
    #expect(await agent.expireIfNeeded(now: deadline.addingTimeInterval(500)))
    #expect(await agent.recentTurnCount == 0)
    #expect(await agent.activeNoteID == nil)
    #expect(await store.notes().count == 1)
}

@Test func invalidWriteCannotProduceSuccessfulSaveReply() async throws {
    let (store, folder) = try testStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let call = try toolResponse("append_to_note", .object(["note_id": .string(UUID().uuidString), "expected_revision": .number(1), "text": .string("Change")]))
    let agent = CompanionAgent(store: store, model: ScriptedLanguageModel([call, response("Saved your change!")]))
    let result = try await agent.respond(to: "Change my note", key: "fixture")
    #expect(result.receipts.isEmpty)
    #expect(result.reply.contains("couldn’t save"))
    #expect(await store.notes().isEmpty)
}
