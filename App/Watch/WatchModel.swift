import Foundation
import Observation
import WatchKit

@MainActor @Observable final class WatchModel {
    var state = CompanionViewState()
    var characterData: Data?
    var reachable = false
    var showUndo = false
    var canControl: Bool { state.phase.isIdle || (state.replyDevice == "watch" && state.requestID == localRequest) }
    private let link = CompanionLink()
    private let microphone = MicrophoneCapture()
    private let voice = DeviceVoice()
    private var localRequest: UUID?
    private var capturing = false
    private var packetCount = 0
    private var spokenRequest: UUID?
    private var pendingPlaybackEnd: UUID?
    private var awaitingStart = false
    private var awaitingStop = false
    private var awaitingFinish = false
    private var timeout: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var undoTimer: Task<Void, Never>?
    private var microphoneTask: Task<Void, Never>?
    private var microphoneGeneration = UUID()
    private var waitingCharacter: (Data, CharacterManifest)?
    private var chunkAssembler = CharacterChunkAssembler()
    private var selectedCharacterID: UUID?
    private var displayedCharacterID: UUID?
    private var lastRemoteDate = Date.distantPast
    private var lastRemoteSequence = -1
    private var remoteEpoch: UUID?

    init() {
        if let saved = CharacterStore.load() { characterData = saved.0; state.characterID = saved.1.id; displayedCharacterID = saved.1.id }
        link.receive = { [weak self] in self?.received($0) }
        link.receiveFile = { [weak self] bytes, metadata in self?.receivedCharacter(bytes, metadata) }
        link.connectivityChanged = { [weak self] connected in
            guard let self else { return }; reachable = connected
            if connected { command(.status) }
        }
        link.deliveryError = { [weak self] in
            guard let self else { return }
            if state.phase.isIdle, awaitingStop { return }
            if capturing || awaitingStart || awaitingStop {
                stopCapture(); awaitingStart = false; awaitingStop = false
                state.phase = .error; state.caption = "Connection interrupted"
                state.text = "Try again near your iPhone. Check Notes for saved changes."
            }
        }
    }
    func refresh() { command(.status) }
    func primary() {
        guard canControl else { return }
        switch state.phase {
        case .ready, .confirmed, .error: begin()
        case .listening: finish()
        case .thinking:
            stopCapture(); awaitingStart = false; awaitingStop = true
            state.caption = "Stopping…"; command(.cancel); waitForReply(seconds: 15)
        case .speaking:
            voice.stop()
            finishPlayback(id: localRequest, outcome: .finished, command: .stopSpeaking)
        }
    }
    func begin() {
        guard state.phase.isIdle else { return }
        guard reachable else { unavailable(); return }
        guard state.hasDataSharingConsent == true else { consentRequired(); return }
        voice.stop(); stopCapture(); undoTimer?.cancel(); showUndo = false
        let id = UUID(); localRequest = id; packetCount = 0; awaitingStart = true; awaitingStop = false; awaitingFinish = false
        state.requestID = id; state.replyDevice = "watch"
        state.phase = .thinking; state.caption = "Connecting…"; state.text = ""
        state.undoReceiptID = nil; state.undoExpiresAt = nil; state.sessionExpiresAt = nil
        command(.begin); waitForReply(seconds: 20)
    }
    func submit(_ text: String) {
        guard state.phase.isIdle, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard reachable else { unavailable(); return }
        guard state.hasDataSharingConsent == true else { consentRequired(); return }
        voice.stop(); stopCapture(); undoTimer?.cancel(); showUndo = false
        let id = UUID(); localRequest = id; awaitingStart = true; awaitingStop = false; awaitingFinish = false
        state.requestID = id; state.replyDevice = "watch"
        state.phase = .thinking; state.caption = "Thinking…"; state.text = text
        state.undoReceiptID = nil; state.undoExpiresAt = nil; state.sessionExpiresAt = nil
        command(.text, text: text); waitForReply(seconds: 90)
    }
    func finish() {
        guard capturing, let id = localRequest else { return }
        if microphoneTask != nil && packetCount == 0 {
            stopCapture(); awaitingStart = false; awaitingStop = true
            state.phase = .thinking; state.caption = "Stopping…"; state.text = ""
            command(.cancel); waitForReply(seconds: 15); return
        }
        awaitingFinish = true
        do {
            // Drain while this turn still accepts packets, before sending its final count.
            try microphone.finishCapture()
            guard capturing, localRequest == id else { return }
            stopCapture(); command(.finish, count: packetCount)
            state.phase = .thinking; state.caption = "Thinking…"; waitForReply(seconds: 90)
        } catch is CancellationError { }
        catch {
            guard localRequest == id else { return }
            awaitingFinish = false
            let message = error.localizedDescription
            stopCapture(); command(.cancel, text: message)
            state.phase = .error; state.caption = "Couldn’t listen"; state.text = message
        }
    }
    func undo() {
        guard state.phase.isIdle, let id = state.undoReceiptID else { return }
        showUndo = false; undoTimer?.cancel(); command(.undo, receipt: id)
    }
    func startFresh() {
        guard state.phase.isIdle else { return }
        voice.stop(); stopCapture(); state.text = ""; showUndo = false; command(.startFresh)
    }
    private func command(_ kind: WatchCommand.Kind, text: String? = nil, receipt: UUID? = nil, count: Int? = nil) {
        link.send(WatchCommand(kind: kind, requestID: localRequest ?? UUID(), text: text, receiptID: receipt,
                              packetCount: count, endingPlaybackID: pendingPlaybackEnd), type: "command")
    }
    private func received(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WireEnvelope.self, from: data) else { return }
        if envelope.type == "characterChunk" {
            guard let chunk = try? JSONDecoder().decode(CharacterChunk.self, from: envelope.payload) else { return }
            if let completed = try? chunkAssembler.accept(chunk) {
                installCharacter(completed.image, completed.manifest)
            }
            return
        }
        guard envelope.type == "state",
              let incoming = try? JSONDecoder().decode(CompanionViewState.self, from: envelope.payload) else { return }
        if incoming.epoch == remoteEpoch { guard incoming.sequence > lastRemoteSequence else { return } }
        else { guard incoming.updatedAt >= lastRemoteDate else { return } }
        remoteEpoch = incoming.epoch; lastRemoteSequence = incoming.sequence; lastRemoteDate = incoming.updatedAt
        reachable = true
        selectedCharacterID = incoming.characterID
        if let completed = chunkAssembler.select(incoming.characterID, at: incoming.updatedAt) {
            installCharacter(completed.image, completed.manifest)
        }
        syncCharacter(incoming.characterID)
        // A late status for the previous turn cannot replace a just-started recording.
        if awaitingStart, incoming.requestID != localRequest, incoming.phase.isIdle, incoming.phase != .error { return }
        if awaitingStop, incoming.requestID == localRequest, incoming.phase == .speaking { return }
        // Late partial/state delivery cannot restart capture after local Done.
        if awaitingFinish, incoming.requestID == localRequest, incoming.phase == .listening { return }
        if incoming.requestID == localRequest, incoming.phase != .listening { awaitingFinish = false }
        if incoming.requestID == localRequest || incoming.phase == .error { awaitingStart = false }
        if incoming.phase.isIdle { awaitingStop = false; pendingPlaybackEnd = nil }
        state = incoming
        updateTransientDeadlines()
        guard incoming.replyDevice == "watch", incoming.requestID == localRequest else {
            stopCapture(); voice.stop(); timeout?.cancel()
            if !incoming.phase.isIdle { state.caption = "Continue on iPhone" }
            return
        }
        if incoming.phase == .listening, !capturing, microphoneTask == nil {
            timeout?.cancel(); capturing = true
            let id = localRequest
            let captureToken = UUID(); microphoneGeneration = captureToken
            microphoneTask = Task { [weak self] in
                guard let self else { return }
                defer { if microphoneGeneration == captureToken { microphoneTask = nil } }
                do {
                    try await microphone.start { [weak self] samples, rate in
                        guard let self, capturing, microphoneGeneration == captureToken, localRequest == id, let id else { return }
                        // Keep each WC message below its size limit, including JSON/base64 overhead.
                        for offset in stride(from: 0, to: samples.count, by: 24_000) {
                            let bytes = samples.subdata(in: offset..<min(offset+24_000, samples.count))
                            link.send(VoiceFrame(requestID: id, sequence: packetCount, sampleRate: rate, samples: bytes), type: "audio")
                            packetCount += 1
                        }
                    } failed: { [weak self] failure in
                        guard let self, capturing, microphoneGeneration == captureToken, localRequest == id else { return }
                        let message = failure.localizedDescription
                        stopCapture(); command(.cancel, text: message)
                        state.phase = .error; state.caption = "Couldn’t listen"; state.text = message
                    }
                    try Task.checkCancellation()
                    guard localRequest == id, microphoneGeneration == captureToken else { return }
                    guard capturing else { microphone.stop(); return }
                    timeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(30))
                        guard !Task.isCancelled, let self, capturing, microphoneGeneration == captureToken, localRequest == id else { return }
                        let message = "Try a shorter request. Nothing was sent to the agent."
                        stopCapture(); command(.cancel, text: message); state.phase = .error; state.caption = "Recording ended"
                        state.text = message
                    }
                } catch is CancellationError {
                    if localRequest == id, microphoneGeneration == captureToken { microphone.stop() }
                } catch {
                    guard localRequest == id, microphoneGeneration == captureToken else { return }
                    let message = error.localizedDescription
                    stopCapture(); command(.cancel, text: message); state.phase = .error; state.caption = "Couldn’t listen"; state.text = message
                }
            }
        }
        if incoming.phase != .listening, capturing { stopCapture() }
        if incoming.phase == .speaking, spokenRequest != incoming.requestID, !incoming.text.isEmpty {
            stopCapture(); spokenRequest = incoming.requestID
            let id = incoming.requestID
            do { try voice.speak(incoming.text, preferredID: incoming.preferredVoiceID,
                                 language: incoming.preferredVoiceLanguage) { [weak self] outcome in
                guard let self else { return }
                finishPlayback(id: id, outcome: outcome)
            }} catch { finishPlayback(id: id, outcome: .unavailable) }
        } else if incoming.phase != .speaking { voice.stop() }
        if incoming.phase.isIdle { timeout?.cancel() }
    }
    private func finishPlayback(id: UUID?, outcome: SpeechPlaybackEnd, command kind: WatchCommand.Kind = .playbackEnded) {
        guard let id, localRequest == id, state.requestID == id, state.phase == .speaking else { return }
        timeout?.cancel(); awaitingStop = true; pendingPlaybackEnd = id
        // The text and any saved change remain intact even if the phone cannot
        // acknowledge immediately. Talk is usable as soon as local playback ends.
        state.phase = .ready
        state.caption = outcome.failed ? "Reply ready · audio unavailable" : CompanionPhase.ready.title
        command(kind, text: outcome.failed ? "audioUnavailable" : nil)
    }
    private func updateTransientDeadlines() {
        undoTimer?.cancel(); expiry?.cancel()
        showUndo = state.phase.isIdle && state.undoReceiptID != nil && (state.undoExpiresAt ?? .distantPast) > Date()
        if showUndo, let deadline = state.undoExpiresAt {
            undoTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }; self?.showUndo = false
            }
        }
        if state.phase.isIdle, let deadline = state.sessionExpiresAt {
            if deadline <= Date() { clearTransientContext(); return }
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }; self?.clearTransientContext()
            }
        }
    }
    private func clearTransientContext() {
        state.text = ""; state.noteTitle = nil; state.noteID = nil; state.undoReceiptID = nil
        state.undoExpiresAt = nil; state.sessionExpiresAt = nil; showUndo = false
        state.phase = .ready; state.caption = CompanionPhase.ready.title
    }
    private func waitForReply(seconds: Double) {
        timeout?.cancel()
        let id = localRequest
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, localRequest == id else { return }
            unavailable()
        }
    }
    private func stopCapture() {
        capturing = false; microphoneGeneration = UUID()
        let task = microphoneTask; microphoneTask = nil
        microphone.stop(); task?.cancel(); timeout?.cancel()
    }
    private func consentRequired() {
        state.phase = .error; state.caption = "Review on iPhone"
        state.text = "Open Avatodo Settings on iPhone and allow Meta data sharing before talking."
    }
    private func unavailable() {
        stopCapture(); awaitingStart = false; awaitingStop = false; awaitingFinish = false
        state.phase = .error; state.caption = "iPhone unavailable"
        state.text = "Open Avatodo on your iPhone, then try again. Check Notes for any saved changes."
    }
    private func syncCharacter(_ id: UUID?) {
        if id == nil { characterData = nil; displayedCharacterID = nil; try? CharacterStore.reset(); waitingCharacter = nil }
        else if displayedCharacterID == id, characterData != nil { return }
        else if let saved = CharacterStore.load(), saved.1.id == id { characterData = saved.0; displayedCharacterID = saved.1.id }
        else if let pending = waitingCharacter, pending.1.id == id { installCharacter(pending.0, pending.1); waitingCharacter = nil }
        else { command(.character) }
    }
    private func receivedCharacter(_ image: Data, _ metadata: Data) {
        guard let manifest = try? JSONDecoder().decode(CharacterManifest.self, from: metadata),
              CharacterStore.valid(image), CharacterStore.digest(image) == manifest.sha256 else { return }
        if manifest.id == selectedCharacterID { installCharacter(image, manifest) }
        else if manifest.generatedAt > lastRemoteDate { waitingCharacter = (image, manifest) }
    }
    private func installCharacter(_ image: Data, _ manifest: CharacterManifest) {
        guard manifest.id == selectedCharacterID else { return }
        do { try CharacterStore.save(image, manifest: manifest); characterData = image; displayedCharacterID = manifest.id }
        catch { /* Keep the last valid artwork when transfer preparation fails. */ }
    }
}
