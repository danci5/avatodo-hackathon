import Foundation
import Testing
@testable import AvatodoCore

private func inlineStore() async throws -> (LocalTaskStore, Note, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("avatodo-inline-" + UUID().uuidString)
    let store = try LocalTaskStore(persistence: JSONFilePersistence(url: folder.appendingPathComponent("notes.json")))
    let receipt = try await store.perform(.init(action: .create(id: UUID(), kind: .checklist,
        title: "Groceries", body: "Original text", items: [ChecklistItem(text: "Milk")])))
    return (store, receipt.after!, folder)
}

@Test @MainActor func inlineTypingCoalescesAndReopensWithUndo() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let editor = NoteTextEditingSession(note: note, store: store)
    editor.setTitle("Weekly groceries")
    editor.setBody("One line")
    editor.setBody("One line\nAnd a second line")
    #expect(await editor.flush())
    #expect(!editor.hasUnsavedChanges)
    let saved = try await store.note(id: note.id)
    #expect(saved.title == "Weekly groceries" && saved.body == "One line\nAnd a second line")
    #expect(saved.revision == 2)
    let reopened = try LocalTaskStore(persistence: JSONFilePersistence(url: folder.appendingPathComponent("notes.json")))
    #expect(try await reopened.note(id: note.id) == saved)
    let undoID = try #require(await reopened.undoableReceiptID(for: note.id))
    let undone = try await reopened.perform(.init(action: .undo(receiptID: undoID)))
    #expect(undone.after?.title == note.title && undone.after?.body == note.body)
}

@Test @MainActor func inlineTypingSavesAfterAPauseWithoutASaveButton() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let editor = NoteTextEditingSession(note: note, store: store)
    editor.setBody("Automatically saved while this note stays open")
    try await Task.sleep(for: .milliseconds(950))
    #expect(try await store.note(id: note.id).body == editor.body)
    #expect(!editor.hasUnsavedChanges)
}

@Test @MainActor func inlineTitleEditPreservesSimultaneousVoiceBodyAndChecklistChanges() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let editor = NoteTextEditingSession(note: note, store: store)
    editor.setTitle("Shopping for the weekend")
    _ = try await store.perform(.init(action: .appendBody(id: note.id, revision: 1, text: "Voice addition")))
    _ = try await store.perform(.init(action: .setItemsComplete(id: note.id, revision: 2, itemIDs: [note.items[0].id], isComplete: true)))
    #expect(await editor.flush())
    let saved = try await store.note(id: note.id)
    #expect(saved.title == "Shopping for the weekend")
    #expect(saved.body == "Original text\nVoice addition")
    #expect(saved.items[0].isComplete)
    #expect(editor.body == saved.body)
}

@Test @MainActor func inlineConflictKeepsTypingAndNeverOverwritesVoiceText() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let editor = NoteTextEditingSession(note: note, store: store)
    editor.setBody("My typed replacement")
    let voice = try await store.perform(.init(action: .appendBody(id: note.id, revision: 1, text: "Saved by voice")))
    editor.receive(voice.after!)
    #expect(await editor.flush() == false)
    #expect(editor.hasConflict && editor.body == "My typed replacement")
    #expect(try await store.note(id: note.id).body == "Original text\nSaved by voice")
    await editor.useSavedVersion()
    #expect(!editor.hasUnsavedChanges && !editor.hasConflict)
    #expect(editor.body == "Original text\nSaved by voice")
    editor.setBody(editor.body + "\nMy next addition")
    #expect(await editor.flush())
}

@Test @MainActor func inlineNoOpPreservesReceiptAndEmptyTitleBecomesUntitled() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let editor = NoteTextEditingSession(note: note, store: store)
    let originalUndo = await store.undoableReceiptID(for: note.id)
    editor.setTitle("  Groceries  ")
    #expect(await editor.flush())
    #expect(await store.undoableReceiptID(for: note.id) == originalUndo)
    #expect(editor.title == "  Groceries  ")
    editor.setTitle("")
    editor.setBody("")
    #expect(await editor.flush())
    #expect(try await store.note(id: note.id).title == "Untitled")
    #expect(try await store.note(id: note.id).body.isEmpty == true)
}

private actor InlineSaveGate {
    private var entered = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func pauseOnce() async {
        guard !entered else { return }
        entered = true; waiting?.resume(); waiting = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { waiting = $0 } }
    }
    func resume() { release?.resume(); release = nil }
}

@Test @MainActor func inlineTypingDuringSaveAndConcurrentFlushKeepLatestText() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let gate = InlineSaveGate()
    let editor = NoteTextEditingSession(note: note, store: store) { await gate.pauseOnce() }
    editor.setBody("First edit")
    let first = Task { await editor.flush() }
    await gate.waitUntilEntered()
    editor.setBody("Continued typing while the first save was finishing")
    let second = Task { await editor.flush() }
    await gate.resume()
    #expect(await first.value)
    #expect(await second.value)
    #expect(try await store.note(id: note.id).body == editor.body)
    #expect(!editor.hasUnsavedChanges && !editor.isSaving)
}

@Test @MainActor func inlineInvalidTextIsKeptAndCanBeCorrectedWithoutLosingTheNote() async throws {
    let (store, note, folder) = try await inlineStore(); defer { try? FileManager.default.removeItem(at: folder) }
    let editor = NoteTextEditingSession(note: note, store: store)
    editor.setTitle(String(repeating: "x", count: 241))
    editor.setBody("Keep this draft")
    #expect(await editor.flush() == false)
    #expect(editor.body == "Keep this draft" && editor.problem != nil)
    #expect(try await store.note(id: note.id) == note)
    editor.setTitle("Corrected title")
    #expect(await editor.flush())
    #expect(editor.problem == nil)
    #expect(try await store.note(id: note.id).body == "Keep this draft")
}
