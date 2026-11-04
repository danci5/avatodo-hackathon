import Foundation
import ImageIO

enum CharacterAnimationFrames {
    static func decode(_ data: Data, layout: CharacterAnimationLayout?) throws -> [CGImage] {
        guard CharacterStore.valid(data), let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CharacterFailure.invalid }
        guard let layout else { return [image] }
        guard image.width == layout.width, image.height == layout.height else { throw CharacterFailure.invalid }
        let cell = image.width / layout.columns
        return try (0..<layout.frameCount).map { index in
            guard let frame = image.cropping(to: CGRect(x: (index % layout.columns) * cell, y: (index / layout.columns) * cell,
                                                      width: cell, height: cell)) else { throw CharacterFailure.invalid }
            return frame
        }
    }
}
