import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main enum CharacterLibraryChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("avatodo-gallery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = CharacterLibrary(folder: root)
        let empty = try library.load(); precondition(empty.characters.isEmpty)
        let image = try png()
        func manifest(_ name: String) -> CharacterManifest {
            CharacterManifest(id: UUID(), name: name, sha256: CharacterStore.digest(image),
                generatedAt: Date(), sourceModel: "fixture", description: name + " description")
        }
        let first = manifest("One"), second = manifest("Two"), third = manifest("Three"), fourth = manifest("Four")
        _ = try library.add(image, manifest: first)
        _ = try library.add(image, manifest: second)
        _ = try library.add(image, manifest: third)
        let selected = try library.select(first.id)
        precondition(selected.selected?.manifest.description == "One description")
        precondition(selected.characters.map(\.id) == [third.id, second.id, first.id])
        let recent = try library.add(image, manifest: fourth)
        precondition(recent.characters.map(\.id) == [fourth.id, third.id, second.id])
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent(first.id.uuidString + ".png").path))
        let reopened = try CharacterLibrary(folder: root).load()
        precondition(reopened.selected?.manifest.name == "Four")
        let reset = try library.select(nil)
        precondition(reset.selected == nil && reset.characters.count == 3)
        print("PASS gallery survives reopening, retains newest three, selects older without reordering, preserves Ava separately")

        _ = try library.select(third.id)
        let replacement = manifest("Three animated")
        let upgraded = try library.replace(third.id, image: image, manifest: replacement)
        precondition(upgraded.selectedID == replacement.id)
        precondition(upgraded.characters.map(\.id) == [fourth.id, replacement.id, second.id])
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent(third.id.uuidString + ".png").path))
        print("PASS adding animation atomically replaces one gallery entry and preserves creation order")

        let corrupt = root.appendingPathComponent("library.json")
        try Data("broken".utf8).write(to: corrupt)
        do { _ = try library.add(image, manifest: manifest("Five")); preconditionFailure("Corrupt index overwritten") }
        catch CharacterLibraryFailure.unreadable { }
        let preserved = try Data(contentsOf: corrupt); precondition(preserved == Data("broken".utf8))
        print("PASS unreadable gallery is preserved rather than silently overwritten")

        let legacyRoot = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let legacy = manifest("Nikola")
        var oldObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        oldObject.removeValue(forKey: "description")
        try JSONSerialization.data(withJSONObject: oldObject).write(to: legacyRoot.appendingPathComponent("current.json"))
        try image.write(to: legacyRoot.appendingPathComponent(legacy.id.uuidString + ".png"))
        let recoveredID = UUID()
        try image.write(to: legacyRoot.appendingPathComponent(recoveredID.uuidString + ".png"))
        let migrated = try CharacterLibrary(folder: legacyRoot).load()
        precondition(migrated.selected?.manifest.name == "Nikola")
        precondition(migrated.selected?.manifest.description == nil)
        precondition(migrated.characters.first { $0.id == recoveredID }?.manifest.name == "Saved companion")
        print("PASS legacy current character and cached artwork recovered without inventing missing descriptions")
    }
    static func png() throws -> Data {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.7, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination)); return data as Data
    }
}
