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
              valid(image, manifest: manifest) else { return nil }
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
    static func valid(_ data: Data, manifest: CharacterManifest) -> Bool {
        guard valid(data) else { return false }
        guard let layout = manifest.animationLayout else { return true }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return image.width == layout.width && image.height == layout.height
    }
    static func save(_ data: Data, manifest: CharacterManifest) throws {
        guard valid(data, manifest: manifest), digest(data) == manifest.sha256 else { throw CharacterFailure.invalid }
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

    /// One cached sheet with a fixed cell size and baseline. No generated
    /// video or runtime model calls; the same bounded PNG travels to the Watch.
    static func prepareAnimationSheet(_ data: Data, layout: CharacterAnimationLayout = .twentyPoseV1) throws -> Data {
        let columns = layout.columns, width = layout.width, height = layout.height
        guard data.count <= 16_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sheet = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary), sheet.width >= 600, sheet.height >= 600,
              let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CharacterFailure.invalid }
        let divisions = try sheetDivisions(sheet, columns: columns, rows: layout.rows)
        for index in 0..<layout.frameCount {
            try Task.checkCancellation()
            let column = index % columns, row = index / columns
            guard let crop = sheet.cropping(to: CGRect(x: divisions.x[column], y: divisions.y[row],
                width: divisions.x[column+1]-divisions.x[column], height: divisions.y[row+1]-divisions.y[row]))
            else { throw CharacterFailure.invalid }
            let foreground: CGImage
            #if os(iOS) || os(macOS)
            foreground = (try? foregroundImage(crop)) ?? crop
            #else
            foreground = crop
            #endif
            let clean = try prepareEdgesAndEncode(foreground, requireClearEdges: true)
            guard let cleanSource = CGImageSourceCreateWithData(clean as CFData, nil),
                  let frame = CGImageSourceCreateImageAtIndex(cleanSource, 0, nil) else { throw CharacterFailure.invalid }
            let frameSide = Double(layout.cellSide), inset = frameSide * 0.045
            let contentSide = frameSide - 2 * inset
            let scale = min(contentSide / Double(frame.width), contentSide / Double(frame.height))
            let w = Double(frame.width) * scale, h = Double(frame.height) * scale
            let x = Double(index % columns) * frameSide + (frameSide - w) / 2
            let y = Double(layout.rows - 1 - index / columns) * frameSide + inset
            canvas.draw(frame, in: CGRect(x: x, y: y, width: w, height: h))
        }
        guard let result = canvas.makeImage() else { throw CharacterFailure.invalid }
        let encoded = try encodePNG(result)
        guard valid(encoded) else { throw CharacterFailure.invalid }
        return encoded
    }

    /// Generators approximate grid spacing. Find low-ink gutters near the
    /// expected divisions rather than slicing a mane or head at an exact fraction.
    private static func sheetDivisions(_ image: CGImage, columns: Int, rows: Int) throws -> (x: [Int], y: [Int]) {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w*h*4)
        let counts: ([Int], [Int]) = try rgba.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw CharacterFailure.invalid }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let pixels = raw.bindMemory(to: UInt8.self)
            var xs = [Int](repeating: 0, count: w), ys = [Int](repeating: 0, count: h)
            for y in 0..<h { for x in 0..<w {
                let i = (y*w+x)*4, alpha = Int(pixels[i+3])
                if alpha > 128, min(Int(pixels[i]), Int(pixels[i+1]), Int(pixels[i+2])) * 255 / alpha < 215 {
                    xs[x] += 1; ys[y] += 1
                }
            }}
            return (xs, ys)
        }
        func cuts(_ ink: [Int], parts: Int, crossSize: Int) throws -> [Int] {
            var result = [0]
            let cell = ink.count / parts, radius = max(2, cell * 18 / 100)
            for part in 1..<parts {
                let center = ink.count * part / parts
                let range = max(result.last! + 1, center-radius)...min(ink.count-1, center+radius)
                // Use the middle of a clear gutter, not its first white pixel.
                // Cutting at the first pixel leaves the preceding character
                // flush against its cell edge and can resemble a clipped body.
                let threshold = max(8, crossSize / 40)
                var gutters: [ClosedRange<Int>] = [], start: Int?
                for i in range {
                    if ink[i] <= threshold { if start == nil { start = i } }
                    else if let lower = start { gutters.append(lower...(i-1)); start = nil }
                }
                if let lower = start { gutters.append(lower...range.upperBound) }
                guard let gutter = gutters.min(by: { a, b in
                    abs((a.lowerBound+a.upperBound)/2-center) < abs((b.lowerBound+b.upperBound)/2-center)
                }) else { throw CharacterFailure.invalid }
                let cut = (gutter.lowerBound+gutter.upperBound)/2
                result.append(cut)
            }
            result.append(ink.count)
            return result
        }
        return (try cuts(counts.0, parts: columns, crossSize: h), try cuts(counts.1, parts: rows, crossSize: w))
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

    private static func prepareEdgesAndEncode(_ input: CGImage, requireClearEdges: Bool = false) throws -> Data {
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
            if requireClearEdges {
                // Tiny disconnected strips from a neighboring cell must not
                // survive segmentation as a second character fragment.
                var visited = [Bool](repeating: false, count: w * h)
                var components: [(pixels: [Int], edge: Bool)] = []
                for seed in 0..<(w*h) where !visited[seed] && pixels[seed*4+3] > 24 {
                    var component = [seed], head = 0, edge = false
                    visited[seed] = true
                    while head < component.count {
                        let p = component[head]; head += 1
                        let x = p % w, y = p / w
                        edge = edge || x == 0 || y == 0 || x == w-1 || y == h-1
                        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x+dx, ny = y+dy
                            guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                            let n = ny*w+nx
                            if !visited[n], pixels[n*4+3] > 24 { visited[n] = true; component.append(n) }
                        }}
                    }
                    components.append((component, edge))
                }
                let largest = components.map { $0.pixels.count }.max() ?? 0
                for component in components where component.edge && component.pixels.count < largest / 10 {
                    for p in component.pixels { for c in 0..<4 { pixels[p*4+c] = 0 } }
                }
                // Wrong row/column counts cut characters at cell edges. Reject
                // those sheets rather than caching heads or limbs as full frames.
                func solid(_ position: Int) -> Bool {
                    let i = position * 4, alpha = Int(pixels[i+3])
                    guard alpha > 200 else { return false }
                    // Ignore faint provider shadows/white mask fringes at edges.
                    return min(Int(pixels[i]), Int(pixels[i+1]), Int(pixels[i+2])) * 255 / alpha < 215
                }
                let top = (0..<w).filter { solid($0) }.count
                let bottom = (0..<w).filter { solid((h-1)*w+$0) }.count
                let left = (0..<h).filter { solid($0*w) }.count
                let right = (0..<h).filter { solid($0*w+w-1) }.count
                // Small fur tips can touch the boundary; broad body cuts cannot.
                guard max(top, bottom) < max(6, w / 6), max(left, right) < max(6, h / 6) else { throw CharacterFailure.invalid }
            }
            var minX=w, minY=h, maxX=0, maxY=0
            for y in 0..<h { for x in 0..<w where pixels[(y*w+x)*4+3] > 0 {
                minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y)
            }}
            guard minX <= maxX, let image = context.makeImage() else { throw CharacterFailure.invalid }
            let x = max(0,minX-12), y = max(0,minY-12)
            return image.cropping(to: CGRect(x:x,y:y,width:min(w-x,maxX-x+13),height:min(h-y,maxY-y+13))) ?? image
        }
        return try encodePNG(output)
    }
    static func encodePNG(_ output: CGImage) throws -> Data {
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
