import SwiftUI

struct CompanionDetailSelection: Identifiable {
    let characterID: UUID?
    let name: String
    var id: String { characterID?.uuidString ?? "default" }
}

#Preview("Companion name and original description") {
    CharacterDetails(model: PhoneModel(), selection: CompanionDetailSelection(characterID: nil, name: "Ava"))
}

struct CharacterDetails: View {
    @Bindable var model: PhoneModel
    let selection: CompanionDetailSelection
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?

    init(model: PhoneModel, selection: CompanionDetailSelection) {
        self.model = model; self.selection = selection
        _name = State(initialValue: selection.name)
    }
    private var character: StoredCharacter? {
        model.characterGallery.first { $0.id == selection.characterID }
    }
    private var originalDescription: String? {
        if selection.characterID == nil {
            return Bundle.main.url(forResource: "DefaultCompanionDescription", withExtension: "txt")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        return character?.manifest.description
    }
    private var validName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CompanionArtwork(data: character?.image, phase: .ready, size: 150,
                        animationLayout: character?.manifest.animationLayout, motionEnabled: false)
                        .frame(maxWidth: .infinity)
                }
                Section {
                    TextField("Companion name", text: $name)
                        .textInputAutocapitalization(.words).submitLabel(.done)
                        .onSubmit { save() }
                } header: { Text("Name") } footer: {
                    Text("You can change the name without generating new artwork. Your companion will use this name when you talk.")
                }
                Section {
                    if let description = originalDescription, !description.isEmpty {
                        Text(description).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("The original description wasn’t saved for this older companion.")
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Original description") } footer: {
                    Text("Original descriptions are kept with the artwork and stay unchanged when you rename your companion.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Companion details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.disabled(!validName || !model.canChangeCharacter)
                }
            }
        }
    }
    private func save() {
        guard validName, model.canChangeCharacter else { return }
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == selection.name { dismiss(); return }
        if model.renameCharacter(selection.characterID, name: name) { dismiss() }
        else { errorMessage = model.alert ?? "The name couldn’t be saved. Please try again."; model.alert = nil }
    }
}
