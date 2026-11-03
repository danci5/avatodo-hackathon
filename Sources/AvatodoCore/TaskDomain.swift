import Foundation

public enum NoteKind: String, Codable, Sendable {
    case note, task, checklist
}

public struct ChecklistItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
    public var isComplete: Bool

    public init(id: UUID = UUID(), text: String, isComplete: Bool = false) {
        self.id = id
        self.text = text
        self.isComplete = isComplete
    }
}

public struct Note: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: NoteKind
    public var title: String
    public var body: String
    public var isComplete: Bool
    public var items: [ChecklistItem]
    public var revision: Int
}

/// Validated local actions, independent of the model provider or UI.
/// Model-facing adapters must resolve names to IDs before issuing a mutation.
public enum TaskAction: Codable, Equatable, Sendable {
    case create(id: UUID, kind: NoteKind, title: String, body: String, items: [ChecklistItem])
    case edit(id: UUID, revision: Int, title: String?, body: String?)
    case appendBody(id: UUID, revision: Int, text: String)
    case setTaskComplete(id: UUID, revision: Int, isComplete: Bool)
    case addItems(id: UUID, revision: Int, items: [ChecklistItem])
    case editItem(id: UUID, revision: Int, itemID: UUID, text: String)
    case removeItems(id: UUID, revision: Int, itemIDs: [UUID])
    case setItemsComplete(id: UUID, revision: Int, itemIDs: [UUID], isComplete: Bool)
    case delete(id: UUID, revision: Int)
    case undo(receiptID: UUID)
}

public struct MutationRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let action: TaskAction

    public init(id: UUID = UUID(), action: TaskAction) {
        self.id = id
        self.action = action
    }
}

/// A receipt describes a committed transition. Replaying a request returns this
/// same receipt; callers should show fresh state separately if later edits exist.
public struct MutationReceipt: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { request.id }
    public let request: MutationRequest
    public let noteID: UUID
    public let before: Note?
    public let after: Note?
    public let committedRevision: Int
}

public enum TaskStoreError: Error, Equatable, Sendable {
    case invalidText
    case limitExceeded
    case duplicateID
    case noteNotFound
    case itemNotFound
    case wrongNoteKind
    case staleRevision(expected: Int, actual: Int)
    case reusedRequestID
    case receiptNotFound
    case ambiguousNote([UUID])
    case invalidSnapshot
}

/// Persist notes, deletion revisions and retry receipts as one transaction.
/// Deleted IDs remain reserved so an old request cannot target a new record.
public struct TaskSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var notes: [UUID: Note] = [:]
    public var revisions: [UUID: Int] = [:]
    public var receipts: [UUID: MutationReceipt] = [:]

    public init() {}
}

struct TaskReducer {
    static let maxItems = 200
    static let maxBodyLength = 50_000

    static func clean(_ text: String, max: Int) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TaskStoreError.invalidText }
        guard value.count <= max else { throw TaskStoreError.limitExceeded }
        return value
    }

    static func validateItems(_ items: [ChecklistItem]) throws -> [ChecklistItem] {
        guard items.count <= maxItems else { throw TaskStoreError.limitExceeded }
        guard Set(items.map(\.id)).count == items.count else { throw TaskStoreError.duplicateID }
        return try items.map { item in
            var result = item
            result.text = try clean(item.text, max: 500)
            return result
        }
    }

    static func apply(_ request: MutationRequest, to snapshot: inout TaskSnapshot) throws -> MutationReceipt {
        if let previous = snapshot.receipts[request.id] {
            guard previous.request == request else { throw TaskStoreError.reusedRequestID }
            return previous
        }

        let id: UUID
        var before: Note?
        var after: Note?

        func existing(_ noteID: UUID, revision: Int) throws -> Note {
            guard let note = snapshot.notes[noteID] else { throw TaskStoreError.noteNotFound }
            guard note.revision == revision else {
                throw TaskStoreError.staleRevision(expected: revision, actual: note.revision)
            }
            return note
        }

        func checklist(_ noteID: UUID, revision: Int) throws -> Note {
            let note = try existing(noteID, revision: revision)
            guard note.kind == .checklist else { throw TaskStoreError.wrongNoteKind }
            return note
        }

        func targets(_ itemIDs: [UUID], in note: Note) throws -> Set<UUID> {
            guard !itemIDs.isEmpty else { throw TaskStoreError.invalidText }
            let selected = Set(itemIDs)
            guard selected.count == itemIDs.count else { throw TaskStoreError.duplicateID }
            guard selected.isSubset(of: Set(note.items.map(\.id))) else { throw TaskStoreError.itemNotFound }
            return selected
        }

        switch request.action {
        case let .create(noteID, kind, title, body, items):
            id = noteID
            guard snapshot.revisions[id] == nil else { throw TaskStoreError.duplicateID }
            guard body.count <= maxBodyLength else { throw TaskStoreError.limitExceeded }
            guard kind == .checklist || items.isEmpty else { throw TaskStoreError.wrongNoteKind }
            after = Note(id: id, kind: kind, title: try clean(title, max: 240), body: body,
                         isComplete: false, items: try validateItems(items), revision: 0)
        case let .edit(noteID, revision, title, body):
            id = noteID
            before = try existing(id, revision: revision)
            after = before
            guard title != nil || body != nil else { throw TaskStoreError.invalidText }
            if let title { after?.title = try clean(title, max: 240) }
            if let body {
                guard body.count <= maxBodyLength else { throw TaskStoreError.limitExceeded }
                after?.body = body
            }
        case let .appendBody(noteID, revision, text):
            id = noteID
            before = try existing(id, revision: revision)
            after = before
            let addition = try clean(text, max: maxBodyLength)
            let current = before!.body
            let body = current.isEmpty ? addition : current + "\n" + addition
            guard body.count <= maxBodyLength else { throw TaskStoreError.limitExceeded }
            after?.body = body
        case let .setTaskComplete(noteID, revision, isComplete):
            id = noteID
            before = try existing(id, revision: revision)
            guard before?.kind == .task else { throw TaskStoreError.wrongNoteKind }
            after = before
            after?.isComplete = isComplete
        case let .addItems(noteID, revision, items):
            id = noteID
            before = try checklist(id, revision: revision)
            guard !items.isEmpty else { throw TaskStoreError.invalidText }
            after = before
            after?.items = try validateItems(before!.items + items)
        case let .editItem(noteID, revision, itemID, text):
            id = noteID
            before = try checklist(id, revision: revision)
            guard let index = before?.items.firstIndex(where: { $0.id == itemID }) else {
                throw TaskStoreError.itemNotFound
            }
            after = before
            after?.items[index].text = try clean(text, max: 500)
        case let .removeItems(noteID, revision, itemIDs):
            id = noteID
            before = try checklist(id, revision: revision)
            let selected = try targets(itemIDs, in: before!)
            after = before
            after?.items.removeAll { selected.contains($0.id) }
        case let .setItemsComplete(noteID, revision, itemIDs, isComplete):
            id = noteID
            before = try checklist(id, revision: revision)
            let selected = try targets(itemIDs, in: before!)
            after = before
            for index in after!.items.indices where selected.contains(after!.items[index].id) {
                after?.items[index].isComplete = isComplete
            }
        case let .delete(noteID, revision):
            id = noteID
            before = try existing(id, revision: revision)
        case let .undo(receiptID):
            guard let original = snapshot.receipts[receiptID] else { throw TaskStoreError.receiptNotFound }
            id = original.noteID
            let currentRevision = snapshot.revisions[id] ?? 0
            guard currentRevision == original.committedRevision else {
                throw TaskStoreError.staleRevision(expected: original.committedRevision, actual: currentRevision)
            }
            before = snapshot.notes[id]
            after = original.before
        }

        let currentRevision = snapshot.revisions[id] ?? 0
        guard currentRevision < Int.max else { throw TaskStoreError.limitExceeded }
        let nextRevision = currentRevision + 1
        after?.revision = nextRevision
        let receipt = MutationReceipt(request: request, noteID: id, before: before,
                                      after: after, committedRevision: nextRevision)
        snapshot.notes[id] = after
        snapshot.revisions[id] = nextRevision
        snapshot.receipts[request.id] = receipt
        return receipt
    }
}
