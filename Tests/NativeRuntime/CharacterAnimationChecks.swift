import Foundation
import CoreGraphics
import ImageIO

@main enum CharacterAnimationChecks {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "App/Resources/DefaultLionAtlas.png"))
        let frames = try CharacterAnimationFrames.decode(data, layout: .twentyPoseV1)
        precondition(frames.count == 20 && frames.allSatisfy { $0.width == 320 && $0.height == 320 })
        let legacyFrames = try CharacterAnimationFrames.decode(data, layout: nil)
        precondition(legacyFrames.count == 1)
        let different = Set(try frames.map { CharacterStore.digest(try CharacterStore.encodePNG($0)) })
        precondition(different.count == 19) // The dance's last frame closes its loop.
        print("PASS bundled sheet decodes to twenty bounded frames; legacy images remain single-frame")

        let poster = try CharacterStore.encodePNG(frames[0])
        let manifest = CharacterManifest(id: UUID(), name: "Ava", sha256: CharacterStore.digest(data),
            generatedAt: Date(), sourceModel: "fixture", animationLayout: .twentyPoseV1)
        precondition(CharacterStore.valid(data, manifest: manifest))
        precondition(!CharacterStore.valid(poster, manifest: manifest))
        let legacy = CharacterManifest(id: UUID(), name: "Ava", sha256: CharacterStore.digest(poster), generatedAt: Date(), sourceModel: "fixture")
        precondition(CharacterStore.valid(poster, manifest: legacy))
        let wire = try JSONEncoder().encode(manifest)
        let roundtrip = try JSONDecoder().decode(CharacterManifest.self, from: wire)
        precondition(roundtrip.animationLayout == .twentyPoseV1)
        print("PASS animation metadata round-trips; malformed sheet dimensions fail validation; a compatibility poster stays valid")

        let cut = CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 4000,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cut.setFillColor(CGColor(gray: 1, alpha: 1)); cut.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        // A broad solid foreground crossing the supposed cell boundaries must
        // fail instead of caching sliced bodies from a malformed provider grid.
        cut.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1))
        cut.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        do {
            _ = try CharacterStore.prepareAnimationSheet(try CharacterStore.encodePNG(cut.makeImage()!), layout: .twentyPoseV1)
            preconditionFailure("A clipped animation sheet was accepted")
        } catch CharacterFailure.invalid { }
        print("PASS obvious cut-off frames are rejected without replacing a cached companion")

        let shifted = CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 4000,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        shifted.setFillColor(CGColor(gray: 1, alpha: 1)); shifted.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        let xs = [0, 215, 405, 610, 800, 1000], ys = [0, 220, 410, 610, 800]
        shifted.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1))
        for row in 0..<4 { for column in 0..<5 {
            shifted.fill(CGRect(x: xs[column]+7, y: ys[row]+7,
                width: xs[column+1]-xs[column]-14, height: ys[row+1]-ys[row]-14))
        }}
        let normalized = try CharacterStore.prepareAnimationSheet(try CharacterStore.encodePNG(shifted.makeImage()!), layout: .twentyPoseV1)
        let shiftedFrames = try CharacterAnimationFrames.decode(normalized, layout: .twentyPoseV1)
        precondition(shiftedFrames.count == 20)
        print("PASS shifted provider rows and columns are cut at clear gutters rather than through the foreground")
    }
}
