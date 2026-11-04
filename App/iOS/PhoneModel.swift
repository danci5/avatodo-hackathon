import Foundation
import Observation
import UIKit
import AvatodoCore

@MainActor @Observable final class PhoneModel {
    var state = CompanionViewState()
    var notes: [Note] = []
    var characterData: Data?
    var characterManifest: CharacterManifest?
    var showUndo = false
    var scopedNoteID: UUID?
    var setupError: String?
    var alert: String?
    var canControl: Bool { state.phase.isIdle || !watchOrigin }
    var generating = false
    var generationStage = ""
    var speaksReplies = UserDefaults.standard.object(forKey: "speaksReplies") as? Bool ?? true {
        didSet { UserDefaults.standard.set(speaksReplies, forKey: "speaksReplies") }
    }
    private var store: LocalTaskStore?
    private var agent: CompanionAgent?
    private let microphone = MicrophoneCapture()
    private let recognition = PhoneRecognition()
    private let voice = DeviceVoice()
    private let link = CompanionLink()
    private var work: Task<Void, Never>?
    private var idle: Task<Void, Never>?
    private var undoTimer: Task<Void, Never>?
    private var captureTimer: Task<Void, Never>?
    private var replyTimer: Task<Void, Never>?
    private var confirmationTimer: Task<Void, Never>?
    private var savedCaption = "Saved"
    private var requestID: UUID?
    private var watchOrigin = false
    private var frames: [Int: VoiceFrame] = [:]
    private var nextFrame = 0
    private var audioRate: Double?
    private var audioFailed = false
    private var acceptingAudio = false
    private var cancellationMessage: String?
    private var recentVoiceRequests: Set<UUID> = []
    private var cancelledWatchRequests: Set<UUID> = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastReceiptByNote: [UUID: UUID] = [:]

    init() {
        if let saved = CharacterStore.load() {
            characterData = saved.0; characterManifest = saved.1
            state.characterID = saved.1.id; state.characterName = saved.1.name
        }
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let store = try LocalTaskStore(persistence: JSONFilePersistence(url: directory.appendingPathComponent("notes.json")))
            self.store = store; agent = CompanionAgent(store: store)
        } catch { setupError = "Your saved notes couldn’t be opened. They have been preserved. Restart the app or restore a backup." }
        refreshKey()
        link.receive = { [weak self] in self?.received($0) }
        link.connectivityChanged = { [weak self] reachable in
            guard let self, reachable else { return }
            self.publish(); self.sendCharacter()
        }
        Task { await refreshNotes() }
    }
    func refreshKey() { state.hasModelKey = ((try? KeychainStore.load()) ?? nil) != nil; publish() }
    func saveKey(_ key: String) throws { try KeychainStore.save(key); refreshKey() }
    func removeKey() throws { try KeychainStore.remove(); refreshKey() }
    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }
    func refreshNotes() async {
        guard let store else { return }
        notes = await store.notes()
        var undoable: [UUID: UUID] = [:]
        for note in notes { undoable[note.id] = await store.undoableReceiptID(for: note.id) }
        lastReceiptByNote = undoable
    }
    private func publish() {
        state.sequence += 1; state.updatedAt = Date(); link.sendState(state)
    }
    private func setPhase(_ phase: CompanionPhase, caption: String? = nil, text: String? = nil) {
        state.phase = phase; state.caption = caption ?? phase.title
        if let text { state.text = text }
        publish()
    }
    func primary(scope: UUID? = nil) {
        guard canControl else { return }
        switch state.phase {
        case .ready, .confirmed, .error: begin(scope: scope)
        case .listening: finish()
        case .thinking: cancel()
        case .speaking: stopSpeaking()
        }
    }
    func begin(scope: UUID? = nil, fromWatch: Bool = false, id: UUID = UUID()) {
        guard state.phase.isIdle, work == nil else { if fromWatch { publish() }; return }
        if fromWatch, recentVoiceRequests.contains(id) || cancelledWatchRequests.contains(id) { publish(); return }
        guard agent != nil, setupError == nil else { return }
        guard state.hasModelKey else { setPhase(.error, text: "Add your Meta API key in iPhone Settings first."); return }
        voice.stop(); confirmationTimer?.cancel(); replyTimer?.cancel(); undoTimer?.cancel(); idle?.cancel(); showUndo = false
        cancellationMessage = nil; state.resultIsMutation = false
        state.sessionExpiresAt = nil; state.undoExpiresAt = nil
        state.undoReceiptID = nil; state.noteTitle = scope.flatMap { note($0)?.title }; state.noteID = scope
        scopedNoteID = scope; watchOrigin = fromWatch; requestID = id; state.requestID = id
        state.replyDevice = fromWatch ? "watch" : "phone"
        frames = [:]; nextFrame = 0; audioRate = nil; audioFailed = false; acceptingAudio = false
        if fromWatch {
            if recentVoiceRequests.count >= 80 { recentVoiceRequests.removeAll() }
            recentVoiceRequests.insert(id)
        }
        if fromWatch { startBackgroundWork() }
        // Request authorization before the Watch starts sending audio.
        setPhase(.thinking, caption: "Preparing microphone…", text: "")
        work = Task { [weak self] in
            guard let self else { return }
            defer { work = nil }
            do {
                _ = await agent?.expireIfNeeded()
                await agent?.setPresentingReply(true)
                try await recognition.start { [weak self] text in
                    guard let self, self.requestID == id, self.state.phase == .listening else { return }
                    self.state.text = text; self.publish()
                } failed: { [weak self] in
                    guard let self, self.requestID == id, self.state.phase == .listening else { return }
                    self.cancel(message: AudioFailure.unavailable.localizedDescription)
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                state.speechReady = true; acceptingAudio = fromWatch
                setPhase(.listening, text: "")
                if !fromWatch {
                    try await microphone.start { [weak self] data, rate in
                        guard let self, self.requestID == id, self.state.phase == .listening else { return }
                        do { try self.recognition.append(data, sampleRate: rate) }
                        catch { self.audioFailed = true; self.cancel(message: error.localizedDescription) }
                    }
                }
                captureTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(fromWatch ? 30 : 60))
                    guard !Task.isCancelled, self?.requestID == id else { return }
                    // A bounded recording ends capture, never silently commits a partial request.
                    self?.cancel(message: "Recording reached its limit. Try a shorter request or type on iPhone.")
                }
            } catch is CancellationError { finishCancelled() } catch { fail(error) }
        }
    }
    func submitText(_ text: String, scope: UUID? = nil, fromWatch: Bool = false, id: UUID = UUID()) {
        guard state.phase.isIdle, work == nil else { if fromWatch { publish() }; return }
        if fromWatch, cancelledWatchRequests.contains(id) { publish(); return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scopedNoteID = scope; watchOrigin = fromWatch; requestID = id; state.requestID = id
        state.replyDevice = fromWatch ? "watch" : "phone"
        state.noteTitle = scope.flatMap { note($0)?.title }; state.noteID = scope
        showUndo = false; confirmationTimer?.cancel(); undoTimer?.cancel(); replyTimer?.cancel(); idle?.cancel(); voice.stop()
        cancellationMessage = nil; state.resultIsMutation = false
        state.undoReceiptID = nil; state.undoExpiresAt = nil; state.sessionExpiresAt = nil
        if fromWatch { startBackgroundWork() }
        work = Task { [weak self] in await self?.respond(text, id: id); self?.work = nil }
    }
    func finish(packetCount: Int? = nil) {
        guard state.phase == .listening, work == nil, let id = requestID else { return }
        captureTimer?.cancel(); microphone.stop()
        setPhase(.thinking, caption: "Finishing transcription…")
        work = Task { [weak self] in
            guard let self else { return }
            defer { work = nil }
            do {
                if watchOrigin {
                    guard let packetCount, packetCount > 0, packetCount <= 1800 else { throw AudioFailure.incompleteAudio }
                    for _ in 0..<20 where nextFrame < packetCount && !audioFailed {
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard nextFrame == packetCount, frames.isEmpty, !audioFailed else { throw AudioFailure.incompleteAudio }
                }
                guard !audioFailed else { throw AudioFailure.incompleteAudio }
                acceptingAudio = false
                let text = try await recognition.finish()
                try Task.checkCancellation()
                guard requestID == id else { return }
                await respond(text, id: id)
            } catch is CancellationError { if requestID == id { finishCancelled() } }
            catch { fail(error) }
        }
    }
    private func respond(_ text: String, id: UUID) async {
        do {
            guard let agent, let key = try KeychainStore.load() else { throw MetaError.missingKey }
            setPhase(.thinking, caption: "Thinking…", text: text)
            _ = await agent.expireIfNeeded()
            await agent.setPresentingReply(true)
            let outcome = try await agent.respond(to: text, requestID: id, key: key, scopedTo: scopedNoteID)
            await refreshNotes()
            guard requestID == id else { return }
            state.resultIsMutation = !outcome.receipts.isEmpty
            state.text = outcome.reply; state.noteID = outcome.activeNoteID
            state.noteTitle = outcome.activeNoteID.flatMap { note($0)?.title }
            state.undoReceiptID = outcome.receipts.last?.id
            for receipt in outcome.receipts { lastReceiptByNote[receipt.noteID] = receipt.id }
            showUndo = state.undoReceiptID != nil
            savedCaption = outcome.receipts.last.map(Self.confirmation) ?? "Saved"
            if speaksReplies && !Task.isCancelled {
                setPhase(.speaking, caption: outcome.receipts.isEmpty ? nil : savedCaption)
                if watchOrigin {
                    // Watch speaks locally; a bounded watchdog prevents a lost playback acknowledgement blocking the session.
                    replyTimer = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(90))
                        guard !Task.isCancelled, self?.requestID == id else { return }
                        self?.readyAfterReply()
                    }
                    endBackgroundWork()
                } else {
                    do { try voice.speak(outcome.reply) { [weak self] in self?.readyAfterReply() } }
                    catch { readyAfterReply() }
                }
            } else { readyAfterReply() }
        } catch is CancellationError { await refreshNotes(); finishCancelled() }
        catch { await refreshNotes(); fail(error) }
    }
    func stopSpeaking() {
        guard canControl, state.phase == .speaking else { return }
        voice.stop(); readyAfterReply()
    }
    private func readyAfterReply() {
        replyTimer?.cancel(); state.sessionExpiresAt = Date().addingTimeInterval(300)
        state.undoExpiresAt = showUndo ? Date().addingTimeInterval(5) : nil
        if state.resultIsMutation {
            setPhase(.confirmed, caption: savedCaption)
            let id = requestID
            confirmationTimer?.cancel()
            confirmationTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, requestID == id, state.phase == .confirmed else { return }
                setPhase(.ready)
            }
        } else { setPhase(.ready) }
        Task { await agent?.setPresentingReply(false) }
        endBackgroundWork(); scheduleIdle()
        if showUndo {
            undoTimer?.cancel()
            undoTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.showUndo = false; self?.state.undoReceiptID = nil; self?.state.undoExpiresAt = nil; self?.publish()
            }
        }
    }
    func cancel(message: String? = nil) {
        cancellationMessage = message; acceptingAudio = false
        captureTimer?.cancel(); microphone.stop(); recognition.cancel(); work?.cancel()
        if work != nil { setPhase(.thinking, caption: "Stopping…", text: message) }
        else { finishCancelled() }
    }
    private func finishCancelled() {
        if let message = cancellationMessage {
            cancellationMessage = nil
            fail(AudioMessage(message: message))
        } else { readyAfterReply() }
    }
    private func fail(_ error: Error) {
        acceptingAudio = false; microphone.stop(); recognition.cancel(); captureTimer?.cancel()
        state.sessionExpiresAt = Date().addingTimeInterval(300)
        state.undoReceiptID = nil; state.undoExpiresAt = nil; showUndo = false
        setPhase(.error, text: error.localizedDescription)
        Task { await agent?.setPresentingReply(false) }; endBackgroundWork(); scheduleIdle()
    }
    func startFresh() {
        guard state.phase.isIdle, work == nil else { return }
        voice.stop(); confirmationTimer?.cancel(); undoTimer?.cancel(); showUndo = false; scopedNoteID = nil
        state.sessionExpiresAt = nil; state.undoExpiresAt = nil; state.resultIsMutation = false
        state.text = ""; state.noteID = nil; state.noteTitle = nil; state.undoReceiptID = nil; state.requestID = nil
        Task { _ = await agent?.startFresh() }; setPhase(.ready); scheduleIdle()
    }
    private func scheduleIdle() {
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(301))
            guard !Task.isCancelled, let self, state.phase.isIdle else { return }
            if await agent?.expireIfNeeded() == true {
                state.text = ""; state.noteID = nil; state.noteTitle = nil; state.undoReceiptID = nil
                scopedNoteID = nil; showUndo = false; state.sessionExpiresAt = nil; state.undoExpiresAt = nil; setPhase(.ready)
            }
        }
    }
    func mutation(_ action: TaskAction) async {
        guard let store else { return }
        do {
            let receipt = try await store.perform(MutationRequest(action: action))
            lastReceiptByNote[receipt.noteID] = receipt.id
            await refreshNotes()
        } catch { alert = "That change wasn’t saved. The note may have changed; open it again and retry." }
    }
    func undoID(for noteID: UUID) -> UUID? { lastReceiptByNote[noteID] }
    func undo(receiptID: UUID? = nil) {
        guard state.phase.isIdle, work == nil, let receipt = receiptID ?? state.undoReceiptID, let store else { return }
        showUndo = false; undoTimer?.cancel()
        Task {
            do {
                let result = try await store.perform(MutationRequest(action: .undo(receiptID: receipt)))
                lastReceiptByNote[result.noteID] = nil; state.undoReceiptID = nil; state.undoExpiresAt = nil
                await refreshNotes(); setPhase(.ready, text: "Undone."); scheduleIdle()
            } catch {
                let message = "This note has changed since that action. Open the note to make your correction."
                alert = message; state.undoReceiptID = nil; state.undoExpiresAt = nil
                setPhase(.error, text: message)
            }
        }
    }
    func createCharacter(description: String, name: String) async {
        guard !generating, state.phase.isIdle, work == nil else { return }
        generating = true; generationStage = "Creating with Muse Image…"
        defer { generating = false }
        do {
            guard let key = try KeychainStore.load() else { throw MetaError.missingKey }
            let original = try await MetaClient().generateCharacter(description: description, key: key)
            generationStage = "Preparing your companion…"
            let prepared = try await Task.detached(priority: .userInitiated) { try CharacterStore.prepare(original) }.value
            let manifest = CharacterManifest(id: UUID(), name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)),
                sha256: CharacterStore.digest(prepared), generatedAt: Date(), sourceModel: MetaClient.imageModel)
            try CharacterStore.save(prepared, manifest: manifest)
            characterData = prepared; characterManifest = manifest
            state.characterID = manifest.id; state.characterName = manifest.name.isEmpty ? "Avatodo" : manifest.name
            publish(); sendCharacter()
        } catch { alert = error.localizedDescription }
    }
    func useDefaultCharacter() {
        do {
            try CharacterStore.reset(); link.cancelCharacterTransfers()
            characterData = nil; characterManifest = nil; state.characterID = nil; state.characterName = "Avatodo"; publish()
        }
        catch { alert = error.localizedDescription }
    }
    private func sendCharacter(retryForeground: Bool = false) {
        guard let manifest = characterManifest else { return }
        link.transferCharacter(url: CharacterStore.url(for: manifest.id), manifest: manifest, retryForeground: retryForeground)
    }
    private func received(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WireEnvelope.self, from: data) else { return }
        if envelope.type == "audio", let frame = try? JSONDecoder().decode(VoiceFrame.self, from: envelope.payload) {
            receiveFrame(frame); return
        }
        guard envelope.type == "command", let command = try? JSONDecoder().decode(WatchCommand.self, from: envelope.payload) else { return }
        switch command.kind {
        case .status: publish(); sendCharacter()
        case .character: sendCharacter(retryForeground: true)
        case .begin: begin(fromWatch: true, id: command.requestID)
        case .text: if let text = command.text { submitText(text, fromWatch: true, id: command.requestID) }
        case .finish: if watchOrigin && requestID == command.requestID { finish(packetCount: command.packetCount) }
        case .cancel:
            if cancelledWatchRequests.count >= 80 { cancelledWatchRequests.removeAll() }
            cancelledWatchRequests.insert(command.requestID)
            if watchOrigin && requestID == command.requestID { cancel(message: command.text) }
            else { publish() }
        case .undo: undo(receiptID: command.receiptID)
        case .startFresh: startFresh()
        case .stopSpeaking, .playbackEnded:
            if watchOrigin && requestID == command.requestID && state.phase == .speaking { readyAfterReply() }
        }
    }
    private func receiveFrame(_ frame: VoiceFrame) {
        guard watchOrigin, requestID == frame.requestID,
              acceptingAudio else { return }
        guard frame.sequence >= nextFrame, frame.sequence < nextFrame + 100, frames.count < 100,
              frame.samples.count <= 32_768 else { return }
        if let rate = audioRate, rate != frame.sampleRate { audioFailed = true; return }
        audioRate = frame.sampleRate; frames[frame.sequence] = frame
        do {
            while let next = frames.removeValue(forKey: nextFrame) {
                try recognition.append(next.samples, sampleRate: next.sampleRate); nextFrame += 1
            }
        } catch { audioFailed = true }
    }
    private static func confirmation(_ receipt: MutationReceipt) -> String {
        switch receipt.request.action {
        case let .setItemsComplete(_, _, ids, complete):
            let count = ids.count
            return "\(complete ? "Checked off" : "Reopened") \(count) \(count == 1 ? "item" : "items")"
        case let .create(_, kind, _, _, _):
            return kind == .checklist ? "List saved" : (kind == .task ? "Task saved" : "Note saved")
        case .delete: return "Deleted"
        case .undo: return "Undone"
        default: return "Updated"
        }
    }
    private func startBackgroundWork() {
        endBackgroundWork()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish Watch request") { [weak self] in
            Task { @MainActor [weak self] in self?.cancel(message: "Open Avatodo on iPhone to continue. Check Notes for any saved changes."); self?.endBackgroundWork() }
        }
    }
    private func endBackgroundWork() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}

private struct AudioMessage: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
