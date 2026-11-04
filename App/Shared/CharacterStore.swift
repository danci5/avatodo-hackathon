import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
#if os(iOS) || os(macOS)
import Vision
import CoreImage
#endif

struct CharacterStore {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion", isDirectory: true)
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func load() -> (Data, CharacterManifest)? {
        guard let bytes = try? Data(contentsOf: folder.appendingPathComponent("current.json")),
              let manifest = try? JSONDecoder().decode(CharacterManifest.self, from: bytes),
              let image = try? Data(contentsOf: url(for: manifest.id)), digest(image) == manifest.sha256,
              valid(image) else { return nil }
        return (image, manifest)
    }
    static func url(for id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".png") }
    static func valid(_ data: Data) -> Bool {
        guard data.count <= 4_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2048, height <= 2048 else { return false }
        return true
    }
    static func save(_ data: Data, manifest: CharacterManifest) throws {
        guard valid(data), digest(data) == manifest.sha256 else { throw CharacterFailure.invalid }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url(for: manifest.id), options: .atomic)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("current.json"), options: .atomic)
    }
    static func reset() throws {
        let url = folder.appendingPathComponent("current.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    /// Local foreground separation, crop/resize, then native motion. This is not generated video.
    /// Apple Vision keeps soft character edges when available; edge-connected white
    /// removal is a deterministic fallback for providers' requested plain-white output.
    static func prepare(_ data: Data) throws -> Data {
        guard data.count <= 16_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let input = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
              ] as CFDictionary) else { throw CharacterFailure.invalid }
        let foreground: CGImage
        #if os(iOS) || os(macOS)
        foreground = (try? foregroundImage(input)) ?? input
        #else
        foreground = input
        #endif
        return try prepareEdgesAndEncode(foreground)
    }

    #if os(iOS) || os(macOS)
    private static func foregroundImage(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw CharacterFailure.invalid
        }
        let pixels = try observation.generateMaskedImage(ofInstances: observation.allInstances,
            from: handler, croppedToInstancesExtent: false)
        let foreground = CIImage(cvPixelBuffer: pixels)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let output = context.createCGImage(foreground, from: foreground.extent) else {
            throw CharacterFailure.invalid
        }
        return output
    }
    #endif

    private static func prepareEdgesAndEncode(_ input: CGImage) throws -> Data {
        let w = input.width, h = input.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let output: CGImage = try rgba.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress, let context = CGContext(data: base, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterFailure.invalid }
            context.draw(input, in: CGRect(x: 0, y: 0, width: w, height: h))
            let pixels = raw.bindMemory(to: UInt8.self)
            var seen = [Bool](repeating: false, count: w * h), queue: [Int] = []
            func add(_ p: Int) {
                guard !seen[p] else { return }; seen[p] = true
                let i = p * 4, alpha = Int(pixels[i+3])
                if alpha < 8 { queue.append(p); return }
                // Read straight colors from our premultiplied buffer. Walking through
                // transparent pixels also removes the white rim of a soft Vision mask.
                let a = min(255, Int(pixels[i]) * 255 / alpha)
                let b = min(255, Int(pixels[i+1]) * 255 / alpha)
                let c = min(255, Int(pixels[i+2]) * 255 / alpha)
                if min(a,b,c) > 235 && max(a,b,c) - min(a,b,c) < 20 { queue.append(p) }
            }
            for x in 0..<w { add(x); add((h-1)*w+x) }
            for y in 0..<h { add(y*w); add(y*w+w-1) }
            var cursor = 0
            while cursor < queue.count {
                let p = queue[cursor]; cursor += 1
                for c in 0..<4 { pixels[p*4+c] = 0 }
                let x = p % w, y = p / w
                if x > 0 { add(p-1) }; if x < w-1 { add(p+1) }
                if y > 0 { add(p-w) }; if y < h-1 { add(p+w) }
            }
            var minX=w, minY=h, maxX=0, maxY=0
            for y in 0..<h { for x in 0..<w where pixels[(y*w+x)*4+3] > 0 {
                minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y)
            }}
            guard minX <= maxX, let image = context.makeImage() else { throw CharacterFailure.invalid }
            let x = max(0,minX-12), y = max(0,minY-12)
            return image.cropping(to: CGRect(x:x,y:y,width:min(w-x,maxX-x+13),height:min(h-y,maxY-y+13))) ?? image
        }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw CharacterFailure.invalid }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw CharacterFailure.invalid }
        return bytes as Data
    }
}
enum CharacterFailure: Error, LocalizedError {
    case invalid
    var errorDescription: String? { "That artwork couldn’t be prepared. Your previous companion is still available." }
}
