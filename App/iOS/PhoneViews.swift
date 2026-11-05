import SwiftUI
import AvatodoCore
import GoogleSignInSwift
@preconcurrency import AVFoundation

struct PhoneRoot: View {
    @Bindable var model: PhoneModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var character = false
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            Tab("Companion", systemImage: "sparkles", value: 0) {
                NavigationStack {
                    PhoneCompanion(model: model)
                        .navigationTitle("Avatodo").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Your companion", systemImage: "slider.horizontal.3") { character = true }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Settings", systemImage: "gearshape") { settings = true }
                            }
                        }
                }
            }
            Tab("Notes", systemImage: "note.text", value: 1) {
                NavigationStack { NotesScreen(model: model) }
            }
        }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            do { try DevelopmentBootstrap.importKeyIfProvided(); model.refreshKey() }
            catch { model.alert = error.localizedDescription }
            await DevelopmentAudioProbe.runIfRequested()
            await DevelopmentSpeechProbe.runIfRequested()
            #endif
            await model.refreshNotes()
            await model.drive.restore(notes: model.notes)
            model.drive.changed(model.notes)
        }
        .onOpenURL { model.drive.handle($0) }
        .sheet(isPresented: $settings) { SettingsScreen(model: model) }
        .sheet(isPresented: $character) { CharacterScreen(model: model) }
        .alert("Avatodo", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert ?? "") }
        .overlay {
            if let error = model.setupError { ContentUnavailableView("Notes unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(error)).background(.background) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshVoices(); model.drive.changed(model.notes) }
            else { model.stopVoicePreview() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
            model.refreshVoices()
        }
    }
}

struct PhoneCompanion: View {
    @Bindable var model: PhoneModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typing = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 18) {
                Spacer(minLength: 6)
                Button { model.dance() } label: {
                    CompanionArtwork(data: model.characterData, phase: model.state.phase,
                    size: min(geometry.size.width * 0.7, geometry.size.height * 0.40),
                    celebrationID: model.state.undoReceiptID, animationLayout: model.characterManifest?.animationLayout,
                    reaction: model.state.reaction, reactionID: model.state.reactionID)
                }.buttonStyle(CompanionArtworkButtonStyle()).disabled(!model.state.phase.isIdle || reduceMotion)
                    .accessibilityLabel("Make your companion dance")
                    .frame(maxWidth: .infinity)
                Text(model.state.caption).font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center).contentTransition(.opacity)
                    .frame(minHeight: 28)
                Group {
                    if !model.state.hasModelKey && model.state.text.isEmpty {
                        VStack(spacing: 8) {
                            Text("Your companion is ready.").font(.headline)
                            Text("Add your Meta API key in Settings to start talking.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if model.state.resultIsMutation, let title = model.state.noteTitle, model.state.phase.isIdle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Text(model.state.text).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ConversationText(text: model.state.text, live: model.state.phase == .listening)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(model.state.text.isEmpty ? Color.clear : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                Spacer(minLength: 0)
                ConversationControls(phase: model.state.controlsPhase, showUndo: model.showUndo,
                    primary: { model.primary() }, undo: { model.undo() })
                    .disabled(!model.canControl)
            }
            .padding(.horizontal, 22).padding(.bottom, 12)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.state.phase)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Conversation", systemImage: "ellipsis") {
                        Button("Type a message", systemImage: "keyboard") { typing = true }.disabled(!model.state.phase.isIdle)
                        Button("Start fresh", systemImage: "arrow.counterclockwise") { model.startFresh() }.disabled(!model.state.phase.isIdle)
                    }
                }
            }
            .sheet(isPresented: $typing) { MessageComposer { model.submitText($0) } }
        }
    }
}

struct NotesScreen: View {
    @Bindable var model: PhoneModel
    @State private var creating = false
    var body: some View {
        List {
            if model.notes.isEmpty {
                ContentUnavailableView("Your notes start here", systemImage: "note.text", description: Text("Ask your companion to save an idea or make a list."))
                    .listRowSeparator(.hidden)
            }
            ForEach(model.notes) { note in
                NavigationLink(value: note.id) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(note.title).font(.headline).lineLimit(3)
                        if note.kind == .checklist {
                            Text("\(note.items.filter { !$0.isComplete }.count) items left").font(.subheadline).foregroundStyle(.secondary)
                        } else if !note.body.isEmpty { Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    }.padding(.vertical, 5)
                }
                .swipeActions { Button("Delete", role: .destructive) { Task { await model.mutation(.delete(id: note.id, revision: note.revision)) } } }
            }
        }
        .navigationTitle("Notes")
        .navigationDestination(for: UUID.self) { id in NoteScreen(model: model, id: id) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New note", systemImage: "square.and.pencil") { creating = true } } }
        .sheet(isPresented: $creating) { NewNoteComposer { kind, title, body in
            Task { await model.mutation(.create(id: UUID(), kind: kind, title: title, body: body, items: [])) }
        }}
    }
}

struct NoteScreen: View {
    @Bindable var model: PhoneModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let note = model.note(id), let editor = model.noteEditor(for: note) {
                InlineNoteContent(model: model, note: note, editor: editor).id(id)
            } else { ContentUnavailableView("Note removed", systemImage: "note.text").onAppear { dismiss() } }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InlineNoteContent: View {
    @Bindable var model: PhoneModel
    let note: Note
    @Bindable var editor: NoteTextEditingSession
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: Field?
    @State private var updating = false
    @State private var newItem = ""
    private enum Field: Hashable { case title, body }
    private var id: UUID { note.id }
    var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        TextField("Title", text: Binding(get: { editor.title }, set: { editor.setTitle($0) }), axis: .vertical)
                            .font(.largeTitle.bold()).textFieldStyle(.plain)
                            .focused($focusedField, equals: .title)
                            .accessibilityLabel("Note title")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if note.kind == .task {
                            Button {
                                perform { .setTaskComplete(id: $0.id, revision: $0.revision, isComplete: !$0.isComplete) }
                            } label: { Label(note.isComplete ? "Completed" : "Mark complete", systemImage: note.isComplete ? "checkmark.circle.fill" : "circle") }
                        }
                        TextField("Note", text: Binding(get: { editor.body }, set: { editor.setBody($0) }), axis: .vertical)
                            .font(.body).textFieldStyle(.plain).lineLimit(1...)
                            .focused($focusedField, equals: .body)
                            .accessibilityLabel("Note text")
                            .frame(maxWidth: .infinity, minHeight: note.kind == .checklist ? 28 : 120, alignment: .topLeading)
                        if note.kind == .checklist {
                            VStack(spacing: 0) {
                                ForEach(note.items) { item in
                                    Button {
                                        perform { fresh in .setItemsComplete(id: fresh.id, revision: fresh.revision, itemIDs: [item.id], isComplete: !item.isComplete) }
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isComplete ? Color.blue : .secondary)
                                            Text(item.text).strikethrough(item.isComplete).foregroundStyle(item.isComplete ? .secondary : .primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }.padding(.vertical, 14).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Divider()
                                }
                                HStack {
                                    TextField("Add item", text: $newItem).onSubmit { addItem() }
                                    Button("Add", systemImage: "plus") { addItem() }.labelStyle(.iconOnly).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                                }.padding(.vertical, 14)
                            }
                        }
                        if let receipt = model.undoID(for: id) {
                            Button("Undo last change") {
                                focusedField = nil
                                Task { if await editor.flush() { model.undo(receiptID: model.undoID(for: id) ?? receipt) } }
                            }.font(.subheadline)
                        }
                        if let problem = editor.problem {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(problem).font(.footnote).foregroundStyle(.secondary)
                                HStack(spacing: 24) {
                                    Button("Retry save") { Task { await editor.flush() } }
                                    if editor.hasConflict {
                                        Button("Use saved version") { focusedField = nil; Task { await editor.useSavedVersion() } }
                                    }
                                }.font(.subheadline)
                            }
                        }
                    }.padding(22)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    Button("Update this note") {
                        focusedField = nil
                        Task { if await editor.flush() { updating = true } }
                    }
                        .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
                        .frame(maxWidth: .infinity).padding(.horizontal, 22).padding(.vertical, 12)
                        .disabled(!model.state.phase.isIdle)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil; Task { await editor.flush() } }
                    }
                }
                .sheet(isPresented: $updating, onDismiss: { if model.canControl && !model.state.phase.isIdle { model.cancel() } }) {
                    NoteConversationPanel(model: model, id: id)
                        .presentationDetents([.height(300), .medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(300)))
                }
                .onChange(of: focusedField) { _, value in if value == nil { Task { await editor.flush() } } }
                .onChange(of: scenePhase) { _, value in if value != .active { Task { await editor.flush() } } }
                .onDisappear { Task { await editor.flush() } }
    }
    private func perform(_ action: @escaping @MainActor (Note) -> TaskAction) {
        focusedField = nil
        Task {
            guard await editor.flush(), let fresh = model.note(id) else { return }
            await model.mutation(action(fresh))
        }
    }
    private func addItem() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            guard await editor.flush(), let fresh = model.note(id) else { return }
            let saved = await model.mutation(.addItems(id: fresh.id, revision: fresh.revision, items: [ChecklistItem(text: text)]))
            if saved, newItem.trimmingCharacters(in: .whitespacesAndNewlines) == text { newItem = "" }
        }
    }
}

struct NoteConversationPanel: View {
    @Bindable var model: PhoneModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var typing = false
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                CompanionArtwork(data: model.characterData, phase: model.state.phase, size: 48,
                    animationLayout: model.characterManifest?.animationLayout, reaction: model.state.reaction, reactionID: model.state.reactionID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.state.caption).font(.subheadline.weight(.semibold))
                    Text(model.note(id)?.title ?? "Note").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu("Conversation", systemImage: "ellipsis") {
                    Button("Type an update", systemImage: "keyboard") { typing = true }.disabled(!model.state.phase.isIdle)
                    Button("Start fresh") { model.startFresh() }.disabled(!model.state.phase.isIdle)
                }.labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                Button("Close", systemImage: "xmark") { model.stopSpeaking(); if model.canControl && !model.state.phase.isIdle { model.cancel() }; dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
            }
            ConversationText(text: model.state.text, live: model.state.phase == .listening, compact: true)
            ConversationControls(phase: model.state.controlsPhase, showUndo: model.showUndo, height: 48,
                primary: { model.primary(scope: id) }, undo: { model.undo() })
                .disabled(!model.canControl)
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 14)
        .onAppear { model.begin(scope: id) }
        .sheet(isPresented: $typing) { MessageComposer { model.submitText($0, scope: id) } }
    }
}

struct MessageComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let send: (String) -> Void
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).padding().accessibilityLabel("Message")
                .navigationTitle("Message").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Send") { send(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.presentationDetents([.medium, .large])
    }
}
struct NewNoteComposer: View {
    let save: (NoteKind, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var kind: NoteKind = .note
    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) { Text("Note").tag(NoteKind.note); Text("Task").tag(NoteKind.task); Text("Checklist").tag(NoteKind.checklist) }
                TextField("Title", text: $title, axis: .vertical)
                TextEditor(text: $text).frame(minHeight: 200).accessibilityLabel("Note text")
            }.navigationTitle("New note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(kind, title, text); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}
struct SettingsScreen: View {
    @Bindable var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(model.state.hasModelKey ? "Key stored on this iPhone" : "Add your key", systemImage: model.state.hasModelKey ? "checkmark.shield" : "key")
                    SecureField("Meta API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    HStack(spacing: 24) {
                        Button {
                            do { try model.saveKey(key); key = ""; message = "Stored in iPhone Keychain. Connection not checked." } catch { message = error.localizedDescription }
                        } label: {
                            Text(model.state.hasModelKey ? "Replace key" : "Save key").frame(minHeight: 44)
                        }.disabled(key.isEmpty)
                        if model.state.hasModelKey {
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                do { try model.removeKey(); message = "Key removed." } catch { message = error.localizedDescription }
                            } label: {
                                Text("Remove key").frame(minHeight: 44)
                            }
                        }
                    }.buttonStyle(.borderless)
                    if let message { Text(message).font(.footnote) }
                    Button {
                        message = nil
                        Task { await model.checkConnection() }
                    } label: {
                        HStack {
                            Text(model.checkingConnection ? "Checking connection…" : "Check connection")
                            if model.checkingConnection { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.checkingConnection || !model.state.hasModelKey || !model.metaDataSharingAllowed || !key.isEmpty)
                    if let status = model.connectionStatus {
                        Text(status).font(.footnote).accessibilityLabel("Connection check: " + status)
                    }
                } header: { Text("Meta connection") } footer: {
                    Text("Saving stores your key. Check connection tests your key and lists available models without sending notes or generating content. Try Talk or companion creation to check those features. Requests go directly to Meta; usage charges may apply.")
                }
                Section {
                    Text("The Meta Model API requires users to be aged 18 or older. By allowing Meta requests, you confirm that you meet this requirement.")
                    Text("Meta receives your companion’s name, messages and transcribed words, recent conversation, a list of note titles and details, and the content of notes the agent reads or updates. Creating a companion sends your description to Muse Image. Creating animation poses also sends the companion artwork to Muse Image.")
                    Text("Watch audio goes to your paired iPhone. Apple handles speech recognition, using its speech service when on-device recognition isn’t supported. Avatodo sends text, not raw microphone audio, to Meta.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.metaDataSharingAllowed {
                        Label("Allowed on this iPhone", systemImage: "checkmark.circle")
                        Button("Turn off Meta requests") { model.setMetaDataSharingAllowed(false) }
                    } else {
                        Button("Allow Meta requests") { model.setMetaDataSharingAllowed(true) }
                    }
                    Link("Privacy policy", destination: URL(string: "https://avatodo.com/privacy.html")!)
                } header: { Text("Data sharing with Meta") } footer: {
                    Text("Your permission covers phone and Watch requests. You can turn it off here at any time. Saved notes remain in local storage; data already sent to Meta cannot be recalled by Avatodo. Meta’s privacy policy and terms also apply.")
                }
                Section {
                    Toggle("Speak replies", isOn: $model.speaksReplies)
                    Picker("Reply voice", selection: $model.preferredVoiceID) {
                        Text("Automatic").tag("")
                        if !model.preferredVoiceID.isEmpty,
                           !model.availableVoices.contains(where: { $0.id == model.preferredVoiceID }) {
                            Text("Unavailable — using Automatic").tag(model.preferredVoiceID)
                        }
                        Section("Current language") {
                            ForEach(model.availableVoices.filter { SpeechVoiceSelection.languageMatches($0.language, DeviceVoice.defaultLanguage) }) {
                                Text($0.label).tag($0.id)
                            }
                        }
                        Section("Other languages") {
                            ForEach(model.availableVoices.filter { !SpeechVoiceSelection.languageMatches($0.language, DeviceVoice.defaultLanguage) }) {
                                Text($0.label).tag($0.id)
                            }
                        }
                    }.pickerStyle(.navigationLink)
                    Button(model.previewingVoice ? "Stop preview" : "Preview iPhone voice") {
                        if model.previewingVoice { model.stopVoicePreview() }
                        else { model.previewVoice() }
                    }.disabled(!model.previewingVoice && !model.canPreviewVoice)
                    if let message = model.voicePreviewMessage { Text(message).font(.footnote) }
                    Picker("Watch reply voice", selection: $model.watchVoiceChoice) {
                        Text("Use iPhone voice").tag("iphone")
                        Text("Automatic on Watch").tag("watch-auto")
                        if model.watchVoiceChoice.hasPrefix("watch:"),
                           !model.availableWatchVoices.contains(where: { "watch:" + $0.id == model.watchVoiceChoice }) {
                            Text("Unavailable on Watch, using Automatic").tag(model.watchVoiceChoice)
                        }
                        Section("Available on your Watch") {
                            ForEach(model.availableWatchVoices) { Text($0.label).tag("watch:" + $0.id) }
                        }
                    }.pickerStyle(.navigationLink)
                } header: { Text("Voice") } footer: {
                    Text("Automatic chooses a high-quality available voice for your language. Siri voices aren’t available to Avatodo. Download Enhanced or Premium voices in the device’s Accessibility settings. A voice chosen from the Watch list plays locally, without generating and transferring audio from iPhone. Use iPhone voice generates a short audio reply on this iPhone and sends it to Watch, so its Premium voice pack can stay on iPhone. Delayed or unavailable audio falls back to local Watch speech. Open Avatodo on Watch to refresh its available voices.")
                }
                Section {
                    Text("Upload copies of your notes to an Avatodo folder in your personal Google Drive. Connect Muse to your Drive separately to use those copies.")
                    Picker("File format", selection: Binding(get: { model.drive.copyFormat }, set: { model.drive.setCopyFormat($0, notes: model.notes) })) {
                        ForEach(DriveCopyFormat.allCases, id: \.self) { format in Text(format.title).tag(format) }
                    }.pickerStyle(.navigationLink)
                    if model.drive.connected {
                        if let email = model.drive.accountEmail { Label(email, systemImage: "checkmark.circle").privacySensitive() }
                        Button(model.drive.uploading ? "Uploading…" : "Upload now") { model.drive.changed(model.notes) }
                            .disabled(model.drive.uploading)
                        if let url = model.drive.folderURL { Link("Open Avatodo folder", destination: url) }
                        Button("Disconnect Google Drive", role: .destructive) { model.drive.disconnect() }
                    } else {
                        GoogleSignInButton { Task { await model.drive.connect(notes: model.notes); model.drive.changed(model.notes) } }
                            .disabled(model.drive.connecting || !model.drive.configured)
                        if model.drive.connecting { ProgressView("Connecting…") }
                    }
                    if let message = model.drive.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Google Drive") } footer: {
                    Text("Optional. Notes go directly from this iPhone to your Google account. New local changes update the copies while Avatodo can run. Markdown supports formatted previews on Drive’s web viewer. Plain text is the compatibility option for Drive on iPhone and shows readable text and checklist marks. Changing format updates the same files. Drive edits aren’t imported. Deleting a local note or disconnecting doesn’t delete its Drive copy. Conversation and edit receipts aren’t uploaded. Google manages sign-in securely; no Avatodo server is involved.")
                }
                Section("Conversation") {
                    Button("Start fresh") { model.startFresh(); dismiss() }.disabled(!model.state.phase.isIdle)
                    Text("Conversation stays in memory and clears after five idle minutes. Only notes and their edit receipts are saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Reasoning", selection: Binding(get: { model.reasoningModel }, set: model.selectReasoningModel)) {
                        ForEach(MetaReasoningModel.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }.pickerStyle(.navigationLink).disabled(!model.canChangeReasoningModel)
                    LabeledContent("Artwork", value: "Muse Image")
                    Text("Speech uses Apple recognition on this iPhone, on device when available. Some languages may use Apple’s speech service. Watch audio is relayed to this iPhone.").font(.footnote).foregroundStyle(.secondary)
                    Link("Privacy policy", destination: URL(string: "https://avatodo.com/privacy.html")!)
                    Link("Source code", destination: URL(string: "https://github.com/danci5/avatodo-hackathon")!)
                } header: { Text("About") } footer: {
                    Text("Reasoning applies to phone and Watch conversations. Switch models between replies; your current conversation and saved notes stay available. Model access and usage pricing depend on your Meta account.")
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .onAppear { model.refreshVoices() }
                .onDisappear { model.stopVoicePreview() }
                .onChange(of: key) { _, value in
                    if !value.isEmpty { model.resetConnectionStatus(); message = nil }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct CharacterScreen: View {
    @Bindable var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var previewingAnimations = false
    @State private var previewPhase: CompanionPhase = .ready
    @State private var previewReaction: CompanionReaction?
    @State private var previewReactionID: UUID?
    @State private var inspectedCompanion: CompanionDetailSelection?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        CompanionArtwork(data: model.characterData, phase: previewPhase, size: 160,
                            animationLayout: model.characterManifest?.animationLayout, reaction: previewReaction, reactionID: previewReactionID)
                        Text(model.state.characterName).font(.headline)
                    }.frame(maxWidth: .infinity)
                    if model.characterManifest == nil || model.characterManifest?.animationLayout != nil {
                        Button(previewingAnimations ? "Stop animation preview" : "Preview animations") { previewingAnimations.toggle() }
                    }
                    if model.characterManifest != nil {
                        Button(model.characterManifest?.animationLayout == nil ? "Animate this companion" : "Regenerate animations") { Task { await model.animateSelectedCharacter() } }
                            .disabled(!model.canChangeCharacter || !model.state.hasModelKey || !model.metaDataSharingAllowed)
                    }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        companionChoice(id: nil, name: model.defaultCompanionName, image: nil)
                        ForEach(model.characterGallery) { character in
                            companionChoice(id: character.id, name: character.manifest.name, image: character.image,
                                            animation: character.manifest.animationLayout)
                        }
                    }.padding(.vertical, 4)
                    if !model.characterGalleryAvailable {
                        Text("Your saved gallery couldn’t be opened. Its files have been preserved.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Your companions") } footer: {
                    Text("The default companion and your three most recent creations stay on this iPhone. A new creation replaces the oldest saved custom companion. Tap one to select it, rename it or view its original description.")
                }
                Section {
                    TextField("Name", text: $model.characterDraftName).disabled(model.generating)
                    TextField("Describe your companion", text: $model.characterDraftDescription, axis: .vertical).lineLimit(3...8).disabled(model.generating)
                    Button("Create with Muse Image") {
                        Task { await model.createCharacter(description: model.characterDraftDescription, name: model.characterDraftName) }
                    }
                        .disabled(!model.canChangeCharacter || !model.state.hasModelKey || model.characterDraftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !model.metaDataSharingAllowed { Text("Allow Meta data sharing in Settings before creating a companion.").font(.footnote).foregroundStyle(.secondary) }
                    if model.generating { HStack { ProgressView(); Text(model.generationStage).font(.subheadline) } }
                } header: { Text("Create a new companion") } footer: { Text("These fields create a new companion. To rename an existing one, tap it above. Muse Image creates the artwork and expression poses. Avatodo prepares the animations locally and sends the same companion to your Watch. Creation uses two image requests with your Meta key; playback needs no further model requests.") }
            }.navigationTitle("Your companion").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $inspectedCompanion) { CharacterDetails(model: model, selection: $0) }
        .task(id: previewingAnimations) {
            guard previewingAnimations else {
                previewPhase = .ready; previewReaction = nil; previewReactionID = nil
                return
            }
            for phase in [CompanionPhase.ready, .listening, .thinking, .speaking, .confirmed] {
                guard !Task.isCancelled else { return }
                previewPhase = phase
                do { try await Task.sleep(for: .seconds(phase == .confirmed ? 3 : phase == .speaking ? 2.5 : 1.5)) }
                catch { return }
            }
            previewPhase = .ready
            for reaction in [CompanionReaction.dance, .laugh] {
                guard !Task.isCancelled else { return }
                previewReaction = reaction; previewReactionID = UUID()
                do { try await Task.sleep(for: .seconds(reaction == .dance ? 3 : 2)) } catch { return }
            }
            previewReaction = nil; previewReactionID = nil
            previewPhase = .ready; previewingAnimations = false
        }
        .onChange(of: model.state.characterID) { _, _ in
            previewingAnimations = false; previewPhase = .ready
            previewReaction = nil; previewReactionID = nil
        }
        .onDisappear { previewingAnimations = false; previewPhase = .ready; previewReaction = nil; previewReactionID = nil }
    }
    private func companionChoice(id: UUID?, name: String, image: Data?, animation: CharacterAnimationLayout? = nil) -> some View {
        let selected = model.state.characterID == id
        return Button {
            model.selectCharacter(id)
            inspectedCompanion = CompanionDetailSelection(characterID: id, name: name.isEmpty ? CharacterDefaults.name : name)
        } label: {
            VStack(spacing: 6) {
                CompanionArtwork(data: image, phase: .ready, size: 74, animationLayout: animation, motionEnabled: false)
                HStack(spacing: 4) {
                    Text(name.isEmpty ? CharacterDefaults.name : name).font(.subheadline).lineLimit(2)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                }.frame(minHeight: 34)
            }
            .padding(8).frame(maxWidth: .infinity)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(!model.canChangeCharacter)
        .accessibilityLabel(name.isEmpty ? CharacterDefaults.name : name)
        .accessibilityValue(selected ? "Selected" : "")
    }
}
