import Foundation
import Testing
@testable import AvatodoCore

private struct TestFile {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AvatodoTests-" + UUID().uuidString)
    var persistence: JSONFilePersistence { JSONFilePersistence(url: directory.appendingPathComponent("notes.json")) }
    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

private func expectError(_ expected: TaskStoreError, store: LocalTaskStore, request: MutationRequest) async {
    do {
        _ = try await store.perform(request)
        Issue.record("Expected \(expected), but the mutation succeeded")
    } catch let error as TaskStoreError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func groceryReplacementCompletionUndoAndReopening() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    let listID = UUID()
    let milk = ChecklistItem(text: "Milk")
    let eggs = ChecklistItem(text: "Eggs")
    let bread = ChecklistItem(text: "Bread")
    _ = try await store.perform(.init(action: .create(id: listID, kind: .checklist, title: "Grocery run", body: "", items: [milk, eggs, bread])))
    _ = try await store.perform(.init(action: .editItem(id: listID, revision: 1, itemID: milk.id, text: "Oat milk")))
    let complete = MutationRequest(action: .setItemsComplete(id: listID, revision: 2, itemIDs: [eggs.id, bread.id], isComplete: true))
    let receipt = try await store.perform(complete)
    #expect(receipt.after?.items.map(\.text) == ["Oat milk", "Eggs", "Bread"])
    #expect(receipt.after?.items.map(\.isComplete) == [false, true, true])
    #expect(receipt.after?.items.first?.id == milk.id)

    let reopened = try LocalTaskStore(persistence: file.persistence)
    let retry = try await reopened.perform(complete)
    #expect(retry == receipt)
    let undo = try await reopened.perform(.init(action: .undo(receiptID: complete.id)))
    #expect(undo.after?.revision == 4)
    #expect(undo.after?.items.map(\.isComplete) == [false, false, false])
    #expect(undo.after?.items.first?.text == "Oat milk")
    let reopenedAgain = try LocalTaskStore(persistence: file.persistence)
    let saved = try await reopenedAgain.note(id: listID)
    #expect(saved == undo.after)
}

@Test func invalidMultiItemChangeIsAtomicAndCanBeRetriedCorrectly() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    let id = UUID()
    let eggs = ChecklistItem(text: "Eggs")
    _ = try await store.perform(.init(action: .create(id: id, kind: .checklist, title: "Groceries", body: "", items: [eggs])))
    let requestID = UUID()
    await expectError(.itemNotFound, store: store, request: .init(id: requestID, action: .setItemsComplete(id: id, revision: 1, itemIDs: [eggs.id, UUID()], isComplete: true)))
    let unchanged = try await store.note(id: id)
    #expect(unchanged.revision == 1)
    #expect(unchanged.items.first?.isComplete == false)
    let corrected = try await store.perform(.init(id: requestID, action: .setItemsComplete(id: id, revision: 1, itemIDs: [eggs.id], isComplete: true)))
    #expect(corrected.committedRevision == 2)
}

@Test func simultaneousRetriesCommitOnceAndConflictingReuseFails() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    let request = MutationRequest(action: .create(id: UUID(), kind: .task, title: "Win the Meta Hackathon", body: "", items: []))
    let receipts = try await withThrowingTaskGroup(of: MutationReceipt.self) { group in
        for _ in 0..<16 { group.addTask { try await store.perform(request) } }
        var results: [MutationReceipt] = []
        for try await result in group { results.append(result) }
        return results
    }
    #expect(receipts.count == 16)
    #expect(receipts.allSatisfy { $0 == receipts.first })
    let notes = await store.notes()
    #expect(notes.count == 1)
    #expect(notes.first?.revision == 1)
    await expectError(.reusedRequestID, store: store, request: .init(id: request.id, action: .delete(id: notes[0].id, revision: 1)))
}

@Test func staleEditAndUndoCannotOverwriteNewerWork() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    let id = UUID()
    let create = try await store.perform(.init(action: .create(id: id, kind: .note, title: "Hackathon idea", body: "Watch companion", items: [])))
    _ = try await store.perform(.init(action: .appendBody(id: id, revision: 1, text: "Show the same lion on iPhone.")))
    await expectError(.staleRevision(expected: 1, actual: 2), store: store, request: .init(action: .edit(id: id, revision: 1, title: nil, body: "Old context")))
    await expectError(.staleRevision(expected: 1, actual: 2), store: store, request: .init(action: .undo(receiptID: create.id)))
    let saved = try await store.note(id: id)
    #expect(saved.body == "Watch companion\nShow the same lion on iPhone.")
}

@Test func deletionUndoKeepsIncreasingRevisionAndReservesIdentity() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    let id = UUID()
    _ = try await store.perform(.init(action: .create(id: id, kind: .task, title: "Rehearse demo", body: "", items: [])))
    let deleted = try await store.perform(.init(action: .delete(id: id, revision: 1)))
    #expect(deleted.after == nil)
    let empty = await store.notes()
    #expect(empty.isEmpty)
    await expectError(.duplicateID, store: store, request: .init(action: .create(id: id, kind: .task, title: "Different task", body: "", items: [])))
    let restored = try await store.perform(.init(action: .undo(receiptID: deleted.id)))
    #expect(restored.after?.title == "Rehearse demo")
    #expect(restored.after?.revision == 3)
    let completed = try await store.perform(.init(action: .setTaskComplete(id: id, revision: 3, isComplete: true)))
    #expect(completed.after?.isComplete == true)
}

private enum StorageFailure: Error { case unavailable }
private struct FailingPersistence: TaskPersistence {
    let initial: TaskSnapshot
    func load() throws -> TaskSnapshot? { initial }
    func save(_ snapshot: TaskSnapshot) throws { throw StorageFailure.unavailable }
}

@Test func failedPersistenceReturnsNoReceiptAndLeavesMemoryAndDiskUnchanged() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let original = try LocalTaskStore(persistence: file.persistence)
    let id = UUID()
    let created = try await original.perform(.init(action: .create(id: id, kind: .note, title: "Idea", body: "Saved text", items: [])))
    let loaded = try file.persistence.load()
    let durable = try #require(loaded)
    let failing = try LocalTaskStore(persistence: FailingPersistence(initial: durable))
    do {
        _ = try await failing.perform(.init(action: .edit(id: id, revision: 1, title: nil, body: "Unsaved text")))
        Issue.record("A failed write must not produce a receipt")
    } catch StorageFailure.unavailable { }
    let inMemory = try await failing.note(id: id)
    #expect(inMemory == created.after)
    #expect(try file.persistence.load() == durable)
}

@Test func duplicateTitlesRequireClarification() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    for title in ["Groceries", "GROCERIES"] {
        _ = try await store.perform(.init(action: .create(id: UUID(), kind: .checklist, title: title, body: "", items: [])))
    }
    do {
        _ = try await store.resolveNote(title: " groceries ")
        Issue.record("A voice command must not choose arbitrarily between identical names")
    } catch TaskStoreError.ambiguousNote(let ids) {
        #expect(ids.count == 2)
    }
}

@Test func invalidInputsCannotEnterStoredLists() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    let store = try LocalTaskStore(persistence: file.persistence)
    let duplicate = ChecklistItem(text: "Eggs")
    await expectError(.duplicateID, store: store, request: .init(action: .create(id: UUID(), kind: .checklist, title: "Groceries", body: "", items: [duplicate, duplicate])))
    await expectError(.invalidText, store: store, request: .init(action: .create(id: UUID(), kind: .note, title: " \n ", body: "", items: [])))
    await expectError(.wrongNoteKind, store: store, request: .init(action: .create(id: UUID(), kind: .note, title: "Note", body: "", items: [duplicate])))
    let empty = await store.notes()
    #expect(empty.isEmpty)
}

@Test func corruptedSnapshotsAreNotSilentlyReplaced() async throws {
    let file = TestFile()
    defer { file.cleanUp() }
    var snapshot = TaskSnapshot()
    snapshot.schemaVersion = 99
    try file.persistence.save(snapshot)
    #expect(throws: TaskStoreError.invalidSnapshot) { try LocalTaskStore(persistence: file.persistence) }
    #expect(try file.persistence.load()?.schemaVersion == 99)
}
