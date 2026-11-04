import Foundation

/// Save must commit the complete snapshot or throw without changing durable data.
/// Synchronous persistence keeps the actor transaction free of suspension points.
public protocol TaskPersistence: Sendable {
    func load() throws -> TaskSnapshot?
    func save(_ snapshot: TaskSnapshot) throws
}

/// A dependency-free atomic snapshot adapter. Only one LocalTaskStore may own a URL.
/// Native integration uses one actor for notes, revisions and retry receipts.
public struct JSONFilePersistence: TaskPersistence {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> TaskSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(TaskSnapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: TaskSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public actor LocalTaskStore {
    private let persistence: any TaskPersistence
    private var snapshot: TaskSnapshot

    public init(persistence: any TaskPersistence) throws {
        self.persistence = persistence
        let loaded = try persistence.load() ?? TaskSnapshot()
        guard loaded.schemaVersion == 1,
              loaded.revisions.values.allSatisfy({ $0 > 0 }),
              loaded.notes.allSatisfy({ key, note in key == note.id && loaded.revisions[key] == note.revision }),
              loaded.receipts.allSatisfy({ key, receipt in
                  key == receipt.id && receipt.committedRevision > 0 &&
                  receipt.committedRevision <= (loaded.revisions[receipt.noteID] ?? 0)
              }) else { throw TaskStoreError.invalidSnapshot }
        self.snapshot = loaded
    }

    public func notes() -> [Note] {
        snapshot.notes.values.sorted {
            $0.title == $1.title ? $0.id.uuidString < $1.id.uuidString : $0.title < $1.title
        }
    }

    public func note(id: UUID) throws -> Note {
        guard let note = snapshot.notes[id] else { throw TaskStoreError.noteNotFound }
        return note
    }

    public func resolveNote(title: String) throws -> Note {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = notes().filter { $0.title.caseInsensitiveCompare(title) == .orderedSame }
        guard !matches.isEmpty else { throw TaskStoreError.noteNotFound }
        guard matches.count == 1 else { throw TaskStoreError.ambiguousNote(matches.map(\.id)) }
        return matches[0]
    }

    public func receipt(id: UUID) -> MutationReceipt? { snapshot.receipts[id] }

    /// Returns only a change whose revision still matches the current note.
    /// This restores note-specific Undo availability after restarting the app.
    public func undoableReceiptID(for noteID: UUID) -> UUID? {
        snapshot.receipts.values.first { receipt in
            guard receipt.noteID == noteID,
                  receipt.committedRevision == snapshot.revisions[noteID] else { return false }
            if case .undo = receipt.request.action { return false }
            return true
        }?.id
    }

    public func perform(_ request: MutationRequest) throws -> MutationReceipt {
        try Task.checkCancellation()
        // Work on a copy: validation and failed storage cannot leak partial state.
        var candidate = snapshot
        let receipt = try TaskReducer.apply(request, to: &candidate)
        if candidate != snapshot {
            try persistence.save(candidate)
            snapshot = candidate
        }
        return receipt
    }
}
