import Foundation
import Observation

public enum NoteTextEditingError: Error { case conflict }

/// A live note draft, retained by the phone model while a view comes and goes.
/// Persistence is coalesced; leaving the screen can flush the same pending draft.
@MainActor @Observable public final class NoteTextEditingSession {
    public private(set) var title: String
    public private(set) var body: String
    public private(set) var isSaving = false
    public private(set) var problem: String?
    public private(set) var hasConflict = false
    private var baseline: Note
    private let store: LocalTaskStore
    private let didSave: @MainActor @Sendable () async -> Void
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Bool, Never>?
    @ObservationIgnored private var saveID: UUID?

    public init(note: Note, store: LocalTaskStore,
                didSave: @escaping @MainActor @Sendable () async -> Void = {}) {
        baseline = note; title = note.title; body = note.body
        self.store = store; self.didSave = didSave
    }

    private var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
    public var hasUnsavedChanges: Bool { normalizedTitle != baseline.title || body != baseline.body }

    public func setTitle(_ value: String) { title = value; changed() }
    public func setBody(_ value: String) { body = value; changed() }

    /// Refresh untouched fields only. Dirty fields keep their original baseline
    /// until saved, preserving the comparison needed to detect a real conflict.
    public func receive(_ note: Note) {
        guard note.id == baseline.id else { return }
        if normalizedTitle == baseline.title, note.title != baseline.title { title = note.title; baseline.title = note.title }
        if body == baseline.body, note.body != baseline.body { body = note.body; baseline.body = note.body }
    }

    private func changed() {
        debounce?.cancel()
        if !hasConflict { problem = nil }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self else { return }; _ = await flush()
        }
    }

    /// Concurrent callers join one save loop. Typing that arrives during a disk
    /// write is then saved against that write, rather than the previous revision.
    @discardableResult public func flush() async -> Bool {
        debounce?.cancel(); debounce = nil
        if let saving, let id = saveID {
            let result = await saving.value
            if saveID == id { self.saving = nil; saveID = nil }
            guard result else { return false }
            return hasUnsavedChanges ? await flush() : true
        }
        let id = UUID(); saveID = id
        let task = Task { @MainActor [self] in await persistPending() }
        saving = task
        let result = await task.value
        if saveID == id { saving = nil; saveID = nil }
        guard result else { return false }
        return hasUnsavedChanges ? await flush() : true
    }

    private func persistPending() async -> Bool {
        guard hasUnsavedChanges else { return true }
        isSaving = true
        defer { isSaving = false }
        while hasUnsavedChanges {
            let base = baseline, sentTitle = normalizedTitle, sentBody = body
            do {
                let saved = try await store.saveTextEdit(base: base, title: sentTitle, body: sentBody)
                // An edit started in another field during this write must retain
                // its earlier baseline, in case that field also changed remotely.
                if sentTitle != base.title || normalizedTitle == sentTitle {
                    baseline.title = saved.title
                    if normalizedTitle == sentTitle && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Preserve the user's whitespace and insertion point.
                        if sentTitle == base.title { title = saved.title }
                    }
                }
                if sentBody != base.body || body == sentBody {
                    baseline.body = saved.body
                    if body == sentBody { body = saved.body }
                }
                baseline.revision = saved.revision
                problem = nil; hasConflict = false
                await didSave()
            } catch NoteTextEditingError.conflict {
                hasConflict = true
                problem = "This note changed while you were typing. Your typing is kept here."
                return false
            } catch TaskStoreError.limitExceeded {
                problem = "Use up to 240 characters for the title and 50,000 for the note."
                return false
            } catch {
                problem = "Your typing hasn’t been saved. It’s kept here so you can retry."
                return false
            }
        }
        return true
    }

    /// Explicitly discarding a conflicted draft is the only way an external
    /// update replaces dirty text. Ordinary refreshes never do this silently.
    public func useSavedVersion() async {
        debounce?.cancel(); debounce = nil
        if let saving { _ = await saving.value }
        guard let note = try? await store.note(id: baseline.id) else { return }
        baseline = note; title = note.title; body = note.body
        problem = nil; hasConflict = false
    }
}
