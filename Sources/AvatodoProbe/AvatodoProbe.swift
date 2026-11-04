import Foundation
import AvatodoCore

/// Explicit, opt-in live integration check. It uses fictional notes in its own folder.
/// The credential is read into memory from the development Mac Keychain, never printed.
@main struct AvatodoProbe {
    static func main() async {
        guard CommandLine.arguments.contains("--run-live") else {
            print("Avatodo live Swift check — no API requests sent.")
            print("Run: swift run AvatodoProbe --run-live [--output artifacts/meta-swift-check/results.json]")
            print("Uses your saved development Meta key and makes up to 16 billable model requests with fictional notes.")
            return
        }
        let arguments = CommandLine.arguments
        let output: URL
        if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
            output = URL(fileURLWithPath: arguments[index + 1])
        } else {
            output = URL(fileURLWithPath: "artifacts/meta-swift-check/results.json")
        }
        let started = Date()
        var report = Report(startedAt: started)
        let model = BoundedProbeModel()
        do {
            let key = try developmentKey()
            let folder = output.deletingLastPathComponent().appendingPathComponent("fixture-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let notesURL = folder.appendingPathComponent("notes.json")
            // The fixture folder is owned by this invocation and contains no real user notes.
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = try LocalTaskStore(persistence: JSONFilePersistence(url: notesURL))
            let agent = CompanionAgent(store: store, model: model)

            report.stage = "ordinary_reply"
            let ordinary = try await agent.respond(to: "Hi Ava, how are you? Just answer conversationally. Do not save anything.", key: key)
            try require(ordinary.receipts.isEmpty && !(ordinary.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), "ordinary_reply")
            try require(await store.notes().isEmpty, "ordinary_reply_created_no_notes")
            report.checks.append(Check(name: "ordinary_reply_created_no_notes", passed: true))

            report.stage = "create_checklist"
            let createID = UUID()
            let createText = "Create and save one checklist titled Avatodo integration groceries with exactly three unchecked items: milk, eggs, bread. Do not add anything else."
            let created = try await agent.respond(to: createText, requestID: createID, key: key)
            let notes = await store.notes()
            try require(notes.count == 1 && !created.receipts.isEmpty, "created_exactly_one_checklist")
            let note = notes[0]
            try require(note.kind == .checklist && note.items.count == 3 && note.items.allSatisfy { !$0.isComplete }, "created_three_unchecked_items")
            try require(Set(note.items.map { normalized($0.text) }) == Set(["milk", "eggs", "bread"]), "created_expected_items")
            report.checks.append(Check(name: "created_three_item_checklist", passed: true))

            report.stage = "retry"
            let repeated = try await agent.respond(to: createText, requestID: createID, key: key)
            let retryNotes = await store.notes()
            try require(repeated == created && retryNotes.count == 1, "retry_did_not_duplicate")
            report.checks.append(Check(name: "same_request_retry_did_not_duplicate", passed: true))

            report.stage = "scoped_correction"
            let corrected = try await agent.respond(to: "Replace milk with oat milk in this checklist. Keep eggs and bread unchanged and unchecked.", key: key, scopedTo: note.id)
            let correction = try await store.note(id: note.id)
            try require(!corrected.receipts.isEmpty && correction.items.count == 3, "scoped_correction_committed")
            try require(Set(correction.items.map { normalized($0.text) }) == Set(["oat milk", "eggs", "bread"]), "scoped_correction_expected_items")
            try require(correction.items.allSatisfy { !$0.isComplete }, "correction_kept_items_unchecked")
            report.checks.append(Check(name: "scoped_correction_same_note_id", passed: true))

            report.stage = "check_off"
            let completed = try await agent.respond(to: "Check off eggs and bread in this checklist. Leave oat milk unfinished.", key: key, scopedTo: note.id)
            let checked = try await store.note(id: note.id)
            try require(!completed.receipts.isEmpty && checked.items.filter(\.isComplete).count == 2, "checked_off_two_items")
            try require(checked.items.filter(\.isComplete).allSatisfy { ["eggs", "bread"].contains(normalized($0.text)) }, "checked_expected_items")
            try require(checked.items.first { normalized($0.text) == "oat milk" }?.isComplete == false, "oat_milk_stays_unfinished")
            report.checks.append(Check(name: "checked_eggs_bread_oat_milk_unfinished", passed: true))

            report.stage = "durable_readback"
            let reopened = try LocalTaskStore(persistence: JSONFilePersistence(url: notesURL))
            let durable = try await reopened.note(id: note.id)
            try require(durable == checked, "current_note_matches_disk")
            report.checks.append(Check(name: "atomic_persistence_readback_matches", passed: true))

            report.stage = "undo"
            guard let receipt = completed.receipts.last else { throw ProbeFailure.check("missing_completion_receipt") }
            _ = try await store.perform(MutationRequest(action: .undo(receiptID: receipt.id)))
            let undone = try await store.note(id: note.id)
            try require(undone.items == correction.items && undone.title == correction.title, "undo_restored_previous_items")
            report.checks.append(Check(name: "undo_restores_saved_previous_items", passed: true))
            report.success = true
            report.stage = "complete"
        } catch let failure as ProbeFailure {
            report.failure = failure.safeCategory
        } catch let error as MetaError {
            report.failure = "meta: " + (error.errorDescription ?? "request failed")
        } catch {
            // Never serialize arbitrary provider, credential or process error objects.
            report.failure = "network_or_local_integration_failure"
        }
        report.modelRequestCount = await model.requestCount
        report.finishedAt = Date()
        report.durationSeconds = report.finishedAt!.timeIntervalSince(started)
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: output, options: .atomic)
            print("Live Swift check: \(report.success ? "PASS" : "FAIL") (\(report.checks.count) checks).")
            print("Stage: \(report.stage). Results: \(output.path)")
            if let failure = report.failure { print("Category: " + failure) }
        } catch { print("The evidence file could not be saved.") }
        if !report.success { exit(1) }
    }

    private static func developmentKey() throws -> String {
        #if os(macOS)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "app.avatodo.development.meta", "-a", "avatodo", "-w"]
        let output = Pipe(), errors = Pipe()
        task.standardOutput = output; task.standardError = errors
        try task.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let key = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { throw ProbeFailure.keyUnavailable }
        return key
        #else
        throw ProbeFailure.keyUnavailable
        #endif
    }
    private static func normalized(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func require(_ predicate: Bool, _ name: String) throws {
        guard predicate else { throw ProbeFailure.check(name) }
    }
}
private struct Check: Encodable { let name: String; let passed: Bool }
private struct Report: Encodable {
    var startedAt: Date
    var finishedAt: Date?
    var durationSeconds: Double?
    var modelRequestCount = 0
    var success = false
    var stage = "key_access"
    var failure: String?
    var checks: [Check] = []
    let model = MetaClient.languageModel
    let endpoint = "https://api.meta.ai/v1/chat/completions"
    let implementation = "AvatodoCore MetaClient + CompanionAgent + LocalTaskStore"
    let inputData = "fictional grocery fixture only"
    let evidenceLevel = "macOS live provider and actual shared Swift engine; not native phone/watch device evidence"
}
private enum ProbeFailure: Error {
    case keyUnavailable, check(String)
    var safeCategory: String {
        switch self {
        case .keyUnavailable: "development_key_unavailable"
        case let .check(name): "check_failed: " + name
        }
    }
}

private actor BoundedProbeModel: LanguageModel {
    private(set) var requestCount = 0
    func complete(messages: [JSONValue], tools: [JSONValue], key: String) async throws -> JSONValue {
        guard requestCount < 16 else { throw MetaError.toolLimit }
        requestCount += 1
        return try await MetaClient().complete(messages: messages, tools: tools, key: key)
    }
}
