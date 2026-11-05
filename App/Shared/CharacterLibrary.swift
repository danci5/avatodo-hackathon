import Foundation

enum CharacterDefaults {
    static let name = "Ava"
    static let description = "A little lion with black Wayfarer sunglasses, soft golden fur and a friendly confident smile."
}

struct StoredCharacter: Identifiable {
    let manifest: CharacterManifest
    let image: Data
    var id: UUID { manifest.id }
}

struct CharacterLibrarySnapshot {
    let characters: [StoredCharacter]
    let selectedID: UUID?
    let defaultName: String
    var selected: StoredCharacter? { characters.first { $0.id == selectedID } }
}

/// Phone-owned gallery. One atomic index selects the active companion and retains
/// three recent custom characters; selecting an older character never reorders it.
struct CharacterLibrary {
    private struct Index: Codable {
        var characters: [CharacterManifest]
        var selectedID: UUID?
        var defaultName: String? = nil
    }
    let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("library.json") }
    private var legacyURL: URL { folder.appendingPathComponent("current.json") }
    private func imageURL(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".png") }

    func load() throws -> CharacterLibrarySnapshot {
        let index = try readIndex()
        return snapshot(index)
    }

    @discardableResult func add(_ image: Data, manifest: CharacterManifest) throws -> CharacterLibrarySnapshot {
        guard metadataValid(manifest), CharacterStore.valid(image, manifest: manifest),
              CharacterStore.digest(image) == manifest.sha256 else { throw CharacterLibraryFailure.invalidArtwork }
        let previous = try readIndex()
        guard !previous.characters.contains(where: { $0.id == manifest.id }) else { throw CharacterLibraryFailure.invalidArtwork }
        let characters = [manifest] + previous.characters.filter { readImage($0) != nil }
        let next = Index(characters: Array(characters.prefix(3)), selectedID: manifest.id, defaultName: previous.defaultName)
        try createFolder()
        try image.write(to: imageURL(manifest.id), options: .atomic)
        do { try writeIndex(next) }
        catch { try? FileManager.default.removeItem(at: imageURL(manifest.id)); throw error }
        mirrorSelection(next)
        pruneImages(keeping: Set(next.characters.map(\.id)))
        return snapshot(next)
    }

    @discardableResult func replace(_ id: UUID, image: Data, manifest: CharacterManifest) throws -> CharacterLibrarySnapshot {
        guard manifest.id != id, metadataValid(manifest), CharacterStore.valid(image, manifest: manifest),
              CharacterStore.digest(image) == manifest.sha256 else { throw CharacterLibraryFailure.invalidArtwork }
        var index = try readIndex()
        guard let position = index.characters.firstIndex(where: { $0.id == id }),
              !index.characters.contains(where: { $0.id == manifest.id }) else { throw CharacterLibraryFailure.invalidArtwork }
        index.characters[position] = manifest
        if index.selectedID == id { index.selectedID = manifest.id }
        try image.write(to: imageURL(manifest.id), options: .atomic)
        do { try writeIndex(index) }
        catch { try? FileManager.default.removeItem(at: imageURL(manifest.id)); throw error }
        mirrorSelection(index); pruneImages(keeping: Set(index.characters.map(\.id)))
        return snapshot(index)
    }

    @discardableResult func select(_ id: UUID?) throws -> CharacterLibrarySnapshot {
        var index = try readIndex()
        if let id {
            guard let manifest = index.characters.first(where: { $0.id == id }), readImage(manifest) != nil else {
                throw CharacterLibraryFailure.invalidArtwork
            }
        }
        index.selectedID = id
        try writeIndex(index)
        mirrorSelection(index)
        return snapshot(index)
    }

    @discardableResult func rename(_ id: UUID?, name: String) throws -> CharacterLibrarySnapshot {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw CharacterLibraryFailure.invalidName }
        var index = try readIndex()
        if let id {
            guard let position = index.characters.firstIndex(where: { $0.id == id }),
                  readImage(index.characters[position]) != nil else { throw CharacterLibraryFailure.invalidArtwork }
            // Names are editable. The generation description, artwork identity,
            // creation date and gallery ordering are deliberately unchanged.
            index.characters[position].name = name
        } else { index.defaultName = name }
        try writeIndex(index)
        mirrorSelection(index)
        return snapshot(index)
    }

    private func readIndex() throws -> Index {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return try migrateLegacy() }
        let data = try Data(contentsOf: indexURL)
        guard data.count <= 64_000, let index = try? JSONDecoder().decode(Index.self, from: data),
              index.characters.count <= 3, Set(index.characters.map(\.id)).count == index.characters.count,
              index.characters.allSatisfy(metadataValid),
              index.defaultName == nil || (index.defaultName!.count <= 40 && !index.defaultName!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              index.selectedID == nil || index.characters.contains(where: { $0.id == index.selectedID }) else {
            throw CharacterLibraryFailure.unreadable
        }
        return index
    }

    private func snapshot(_ index: Index) -> CharacterLibrarySnapshot {
        CharacterLibrarySnapshot(characters: index.characters.compactMap { manifest in
            readImage(manifest).map { StoredCharacter(manifest: manifest, image: $0) }
        }, selectedID: index.selectedID, defaultName: index.defaultName ?? CharacterDefaults.name)
    }

    private func metadataValid(_ manifest: CharacterManifest) -> Bool {
        manifest.name.count <= 40 && manifest.sourceModel.count <= 100 &&
        (manifest.description?.count ?? 0) <= 2_000 && manifest.sha256.count == 64 &&
        manifest.sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func readImage(_ manifest: CharacterManifest) -> Data? {
        guard let image = try? Data(contentsOf: imageURL(manifest.id)), CharacterStore.valid(image, manifest: manifest),
              CharacterStore.digest(image) == manifest.sha256 else { return nil }
        return image
    }

    private func createFolder() throws {
        #if os(iOS)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        #else
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #endif
    }

    private func writeIndex(_ index: Index) throws {
        try createFolder()
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    private func migrateLegacy() throws -> Index {
        var current: CharacterManifest?
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            let bytes = try Data(contentsOf: legacyURL)
            guard bytes.count <= 64_000,
                  let saved = try? JSONDecoder().decode(CharacterManifest.self, from: bytes),
                  metadataValid(saved), readImage(saved) != nil else { throw CharacterLibraryFailure.unreadable }
            current = saved
        }

        // Older builds retained PNGs but only kept the current character's metadata.
        // Recover those images with an honest generic name, never inventing their prompts.
        let files = FileManager.default.fileExists(atPath: folder.path)
            ? try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) : []
        let candidates = files.compactMap { url -> (UUID, Date)? in
            guard url.pathExtension.lowercased() == "png", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  id != current?.id else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (id, date)
        }.sorted { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }
        var recovered = current.map { [$0] } ?? []
        for (id, date) in candidates where recovered.count < 3 {
            guard let image = try? Data(contentsOf: imageURL(id)), CharacterStore.valid(image) else { continue }
            recovered.append(CharacterManifest(id: id, name: "Saved companion", sha256: CharacterStore.digest(image),
                generatedAt: date, sourceModel: "local-cache"))
        }
        let index = Index(characters: recovered, selectedID: current?.id)
        try writeIndex(index)
        pruneImages(keeping: Set(recovered.map(\.id)))
        return index
    }

    /// Keep the old selected-image format readable during a rolling app update.
    /// The gallery index is authoritative; this compatibility copy is best effort.
    private func mirrorSelection(_ index: Index) {
        if let selected = index.characters.first(where: { $0.id == index.selectedID }) {
            if let data = try? JSONEncoder().encode(selected) { try? data.write(to: legacyURL, options: .atomic) }
        } else if FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    private func pruneImages(keeping ids: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "png" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !ids.contains(id) else { continue }
            // Preserve unreadable/corrupt files for recovery rather than deleting them.
            guard let data = try? Data(contentsOf: file), CharacterStore.valid(data) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

enum CharacterLibraryFailure: Error, LocalizedError {
    case unreadable, invalidArtwork, invalidName
    var errorDescription: String? {
        switch self {
        case .unreadable: "Your companion gallery couldn’t be opened. The saved files have been preserved."
        case .invalidArtwork: "That saved companion couldn’t be opened. Your current companion hasn’t changed."
        case .invalidName: "Choose a companion name from 1 to 40 characters."
        }
    }
}
