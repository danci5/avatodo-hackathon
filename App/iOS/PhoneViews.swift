import SwiftUI
import AvatodoCore

struct PhoneRoot: View {
    @Bindable var model: PhoneModel
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
            #endif
        }
        .sheet(isPresented: $settings) { SettingsScreen(model: model) }
        .sheet(isPresented: $character) { CharacterScreen(model: model) }
        .alert("Avatodo", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert ?? "") }
        .overlay {
            if let error = model.setupError { ContentUnavailableView("Notes unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(error)).background(.background) }
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
                CompanionArtwork(data: model.characterData, phase: model.state.phase,
                    size: min(geometry.size.width * 0.7, geometry.size.height * 0.40),
                    celebrationID: model.state.undoReceiptID)
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
                ConversationControls(phase: model.state.phase, showUndo: model.showUndo,
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
        .sheet(isPresented: $creating) { NoteEditor(note: nil) { kind, title, body in
            Task { await model.mutation(.create(id: UUID(), kind: kind, title: title, body: body, items: [])) }
        }}
    }
}

struct NoteScreen: View {
    @Bindable var model: PhoneModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var updating = false
    @State private var editing = false
    @State private var newItem = ""
    var body: some View {
        Group {
            if let note = model.note(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(note.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if note.kind == .task {
                            Button {
                                Task { await model.mutation(.setTaskComplete(id: id, revision: note.revision, isComplete: !note.isComplete)) }
                            } label: { Label(note.isComplete ? "Completed" : "Mark complete", systemImage: note.isComplete ? "checkmark.circle.fill" : "circle") }
                        }
                        if !note.body.isEmpty { Text(note.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        if note.kind == .checklist {
                            VStack(spacing: 0) {
                                ForEach(note.items) { item in
                                    Button {
                                        Task { await model.mutation(.setItemsComplete(id: id, revision: note.revision, itemIDs: [item.id], isComplete: !item.isComplete)) }
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
                                    TextField("Add item", text: $newItem).onSubmit { addItem(note) }
                                    Button("Add", systemImage: "plus") { addItem(note) }.labelStyle(.iconOnly).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                                }.padding(.vertical, 14)
                            }
                        }
                        if let receipt = model.undoID(for: id) {
                            Button("Undo last change") { model.undo(receiptID: receipt) }.font(.subheadline)
                        }
                    }.padding(22)
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Update this note") { updating = true }
                        .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
                        .frame(maxWidth: .infinity).padding(.horizontal, 22).padding(.vertical, 12)
                        .disabled(!model.state.phase.isIdle)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "pencil") { editing = true } }
                }
                .sheet(isPresented: $editing) { NoteEditor(note: note) { _, title, body in
                    Task { await model.mutation(.edit(id: id, revision: note.revision, title: title, body: body)) }
                }}
                .sheet(isPresented: $updating, onDismiss: { if model.canControl && !model.state.phase.isIdle { model.cancel() } }) {
                    NoteConversationPanel(model: model, id: id)
                        .presentationDetents([.height(300), .medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(300)))
                }
            } else { ContentUnavailableView("Note removed", systemImage: "note.text").onAppear { dismiss() } }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    private func addItem(_ note: Note) {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }; newItem = ""
        Task { await model.mutation(.addItems(id: id, revision: note.revision, items: [ChecklistItem(text: text)])) }
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
                CompanionArtwork(data: model.characterData, phase: model.state.phase, size: 48)
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
            ConversationControls(phase: model.state.phase, showUndo: model.showUndo, height: 48,
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
struct NoteEditor: View {
    let note: Note?
    let save: (NoteKind, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var kind: NoteKind = .note
    var body: some View {
        NavigationStack {
            Form {
                if note == nil { Picker("Kind", selection: $kind) { Text("Note").tag(NoteKind.note); Text("Task").tag(NoteKind.task); Text("Checklist").tag(NoteKind.checklist) } }
                TextField("Title", text: $title, axis: .vertical)
                TextEditor(text: $text).frame(minHeight: 200).accessibilityLabel("Note text")
            }.navigationTitle(note == nil ? "New note" : "Edit note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(kind, title, text); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.onAppear { title = note?.title ?? ""; text = note?.body ?? ""; kind = note?.kind ?? .note }
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
                    Label(model.state.hasModelKey ? "Key saved on this iPhone" : "Add your key", systemImage: model.state.hasModelKey ? "checkmark.shield" : "key")
                    SecureField("Meta API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button(model.state.hasModelKey ? "Replace key" : "Save key") {
                        do { try model.saveKey(key); key = ""; message = "Saved in iPhone Keychain." } catch { message = error.localizedDescription }
                    }.disabled(key.isEmpty)
                    if model.state.hasModelKey { Button("Remove key", role: .destructive) { do { try model.removeKey(); message = "Key removed." } catch { message = error.localizedDescription } } }
                    if let message { Text(message).font(.footnote) }
                } header: { Text("Meta connection") } footer: { Text("Requests go directly from this iPhone to Meta. Provider access and usage charges may apply. No Avatodo account or hosted server.") }
                Section {
                    Text("Meta AI features are for people aged 18 or older. By allowing Meta requests, you confirm that you meet this requirement.")
                    Text("Meta receives your messages and transcribed words, recent conversation, a list of note titles and details, and the content of notes the agent reads or updates. Creating a companion sends your description to Muse Image.")
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
                Section("Voice") { Toggle("Speak replies", isOn: $model.speaksReplies) }
                Section("Conversation") {
                    Button("Start fresh") { model.startFresh(); dismiss() }.disabled(!model.state.phase.isIdle)
                    Text("Conversation stays in memory and clears after five idle minutes. Only notes and their edit receipts are saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Reasoning", value: "Muse Spark")
                    LabeledContent("Artwork", value: "Muse Image")
                    Text("Speech uses Apple recognition on this iPhone, on device when available. Some languages may use Apple’s speech service. Watch audio is relayed to this iPhone.").font(.footnote).foregroundStyle(.secondary)
                    Link("Privacy policy", destination: URL(string: "https://avatodo.com/privacy.html")!)
                    Link("Source code", destination: URL(string: "https://github.com/danci5/avatodo-hackathon")!)
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct CharacterScreen: View {
    @Bindable var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Ava"
    @State private var description = "A little lion with black Wayfarer sunglasses, soft golden fur and a friendly confident smile."
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CompanionArtwork(data: model.characterData, phase: .ready, size: 160).frame(maxWidth: .infinity)
                    Button("Use the Avatodo lion") { model.useDefaultCharacter() }.disabled(model.generating)
                }
                Section {
                    TextField("Name", text: $name)
                    TextField("Describe your companion", text: $description, axis: .vertical).lineLimit(4...8)
                    Button("Create with Muse Image") { Task { await model.createCharacter(description: description, name: name) } }
                        .disabled(model.generating || !model.state.hasModelKey || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !model.metaDataSharingAllowed { Text("Allow Meta data sharing in Settings before creating a companion.").font(.footnote).foregroundStyle(.secondary) }
                    if model.generating { HStack { ProgressView(); Text(model.generationStage).font(.subheadline) } }
                } header: { Text("Create your own") } footer: { Text("Muse creates the artwork. Avatodo prepares it and adds gentle native animation locally, then sends the same companion to your Watch. Generation uses your Meta key.") }
            }.navigationTitle("Your companion").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
