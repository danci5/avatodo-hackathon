import Foundation

public enum AgentError: Error, LocalizedError, Sendable {
    case busy, invalidArguments, unknownTool, outOfScope, missingTarget
    public var errorDescription: String? {
        switch self {
        case .busy: "Finish the current request first."
        case .invalidArguments: "The requested change was not valid. Read the current note and try again."
        case .unknownTool: "That operation is not available."
        case .outOfScope: "This conversation can only update the selected note."
        case .missingTarget: "Choose or name the note you want to update."
        }
    }
}

public struct AgentToolResult: Sendable {
    public let value: JSONValue
    public let receipt: MutationReceipt?
    public let selectedNoteID: UUID?
}

public enum NoteTools {
    private static let text: JSONValue = .object(["type": .string("string")])
    private static let integer: JSONValue = .object(["type": .string("integer")])
    private static let boolean: JSONValue = .object(["type": .string("boolean")])
    private static let strings: JSONValue = .object(["type": .string("array"), "items": text])

    private static func tool(_ name: String, _ description: String, _ properties: [String: JSONValue]) -> JSONValue {
        .object(["type": .string("function"), "function": .object([
            "name": .string(name), "description": .string(description), "strict": .bool(true),
            "parameters": .object(["type": .string("object"), "properties": .object(properties),
                "required": .array(properties.keys.sorted().map(JSONValue.string)), "additionalProperties": .bool(false)])
        ])])
    }

    public static let catalog: [JSONValue] = [
        tool("search_notes", "Find saved notes by words in titles, bodies or checklist items. Clarify multiple plausible matches.", ["query": text]),
        tool("read_note", "Read a saved note by its actual ID, including current revision and stable item IDs.", ["note_id": text]),
        tool("create_note", "Create a note, task or checklist only when the person asks to save something. Never use for casual conversation. IDs are assigned locally.", [
            "kind": .object(["type": .string("string"), "enum": .array(["note", "task", "checklist"].map(JSONValue.string))]),
            "title": text, "body": text, "items": strings]),
        tool("edit_note", "Change title/body of an existing note. Include the current values for fields that stay the same.", ["note_id": text, "expected_revision": integer, "title": text, "body": text]),
        tool("append_to_note", "Append text to an existing note, preserving its contents.", ["note_id": text, "expected_revision": integer, "text": text]),
        tool("add_checklist_items", "Add items to an existing checklist. This is not limited by conversation length.", ["note_id": text, "expected_revision": integer, "items": strings]),
        tool("edit_checklist_item", "Correct an existing checklist item by ID, preserving that item identity.", ["note_id": text, "expected_revision": integer, "item_id": text, "text": text]),
        tool("set_checklist_items", "Check off or reopen one or several items atomically using their actual IDs.", ["note_id": text, "expected_revision": integer, "item_ids": strings, "completed": boolean]),
        tool("remove_checklist_items", "Remove the selected checklist items. A saved change can be undone.", ["note_id": text, "expected_revision": integer, "item_ids": strings]),
        tool("set_task_complete", "Complete or reopen an existing task.", ["note_id": text, "expected_revision": integer, "completed": boolean]),
        tool("delete_note", "Delete a note only when explicitly requested. Return the saved undo receipt.", ["note_id": text, "expected_revision": integer]),
        tool("undo_change", "Undo a committed change by its actual receipt ID. Stale changes cannot be overwritten.", ["receipt_id": text])
    ]

    public static func execute(name: String, arguments: JSONValue, mutationID: UUID,
                               scope: UUID?, store: LocalTaskStore) async throws -> AgentToolResult {
        guard let args = arguments.object else { throw AgentError.invalidArguments }
        func string(_ key: String) throws -> String {
            guard let value = args[key]?.string else { throw AgentError.invalidArguments }; return value
        }
        func uuid(_ key: String) throws -> UUID {
            guard let id = UUID(uuidString: try string(key)) else { throw AgentError.invalidArguments }; return id
        }
        func revision() throws -> Int {
            guard let value = args["expected_revision"]?.int, value > 0 else { throw AgentError.invalidArguments }; return value
        }
        func stringArray(_ key: String) throws -> [String] {
            guard let values = args[key]?.array, values.count <= 200 else { throw AgentError.invalidArguments }
            return try values.map { guard let value = $0.string else { throw AgentError.invalidArguments }; return value }
        }
        func target() throws -> UUID {
            let id = try uuid("note_id")
            guard scope == nil || scope == id else { throw AgentError.outOfScope }; return id
        }
        func bool(_ key: String) throws -> Bool {
            guard let value = args[key]?.bool else { throw AgentError.invalidArguments }; return value
        }
        func itemIDs() throws -> [UUID] {
            try stringArray("item_ids").map { guard let id = UUID(uuidString: $0) else { throw AgentError.invalidArguments }; return id }
        }

        if name == "search_notes" {
            let query = try string("query").trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count <= 240 else { throw AgentError.invalidArguments }
            let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            let notes = await store.notes().filter { note in
                guard scope == nil || scope == note.id else { return false }
                let haystack = ([note.title, note.body] + note.items.map(\.text)).joined(separator: " ").lowercased()
                return words.allSatisfy(haystack.contains)
            }
            return AgentToolResult(value: .object(["matches": try .encoded(Array(notes.prefix(20))),
                "more_available": .bool(notes.count > 20)]), receipt: nil, selectedNoteID: nil)
        }
        if name == "read_note" {
            let note = try await store.note(id: target())
            return AgentToolResult(value: try .encoded(note), receipt: nil, selectedNoteID: note.id)
        }

        let action: TaskAction
        switch name {
        case "create_note":
            guard scope == nil else { throw AgentError.outOfScope }
            guard let kind = NoteKind(rawValue: try string("kind")) else { throw AgentError.invalidArguments }
            let items = try stringArray("items").map { ChecklistItem(text: $0) }
            action = .create(id: UUID(), kind: kind, title: try string("title"), body: try string("body"), items: items)
        case "edit_note": action = .edit(id: try target(), revision: try revision(), title: try string("title"), body: try string("body"))
        case "append_to_note": action = .appendBody(id: try target(), revision: try revision(), text: try string("text"))
        case "add_checklist_items": action = .addItems(id: try target(), revision: try revision(), items: try stringArray("items").map { ChecklistItem(text: $0) })
        case "edit_checklist_item": action = .editItem(id: try target(), revision: try revision(), itemID: try uuid("item_id"), text: try string("text"))
        case "set_checklist_items": action = .setItemsComplete(id: try target(), revision: try revision(), itemIDs: try itemIDs(), isComplete: try bool("completed"))
        case "remove_checklist_items": action = .removeItems(id: try target(), revision: try revision(), itemIDs: try itemIDs())
        case "set_task_complete": action = .setTaskComplete(id: try target(), revision: try revision(), isComplete: try bool("completed"))
        case "delete_note": action = .delete(id: try target(), revision: try revision())
        case "undo_change":
            let receiptID = try uuid("receipt_id")
            guard let original = await store.receipt(id: receiptID) else { throw TaskStoreError.receiptNotFound }
            guard scope == nil || original.noteID == scope else { throw AgentError.outOfScope }
            action = .undo(receiptID: receiptID)
        default: throw AgentError.unknownTool
        }
        try Task.checkCancellation()
        let receipt = try await store.perform(MutationRequest(id: mutationID, action: action))
        return AgentToolResult(value: .object(["committed": .bool(true), "receipt_id": .string(receipt.id.uuidString),
            "note_id": .string(receipt.noteID.uuidString), "note": try .encoded(receipt.after),
            "message": .string(receipt.after == nil ? "Deleted; undo is available." : "Saved locally.")]),
            receipt: receipt, selectedNoteID: receipt.after?.id)
    }

    public static func failure(_ error: any Error) -> JSONValue {
        let message: String
        switch error {
        case TaskStoreError.staleRevision: message = "The note changed. Read its current revision before updating it."
        case TaskStoreError.noteNotFound, TaskStoreError.itemNotFound: message = "That ID does not exist. Read or search the actual saved notes."
        case TaskStoreError.ambiguousNote: message = "Several notes match. Ask which one the person means."
        case TaskStoreError.reusedRequestID: message = "This request ID already represents another saved change. Do not repeat it."
        case let e as AgentError: message = e.localizedDescription
        default: message = "The change was not saved. Check the arguments and actual current note."
        }
        return .object(["committed": .bool(false), "error": .string(message)])
    }
}
