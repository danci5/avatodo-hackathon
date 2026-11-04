import Foundation
import AVFoundation

@main enum RelayAudioCheck {
    static func main() throws {
        for rate in [16_000.0, 24_000.0, 44_100.0, 48_000.0] {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
            let encoder = RelayPCMEncoder(inputFormat: format)!
            var allBytes = Data()
            let count = Int(rate / 2)
            for offset in stride(from: 0, to: count, by: 2048) {
                let frames = min(2048, count-offset)
                let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
                input.frameLength = AVAudioFrameCount(frames)
                for index in 0..<frames { input.floatChannelData![0][index] = Float(sin(Double(offset+index) / rate * 440 * 2 * .pi) * 0.5) }
                guard let bytes = encoder.encode(input), bytes.count % 2 == 0 else { fatalError("invalid PCM packet") }
                allBytes.append(bytes)
            }
            let samples = allBytes.count / 2
            guard (7400...8100).contains(samples), allBytes.count < 16_500 else { fatalError("incorrect resample duration or bandwidth") }
            var peak = 0, positiveCrossings = 0, previous: Int16 = 0
            allBytes.withUnsafeBytes { bytes in
                for i in 0..<samples {
                    let sample = Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: i*2, as: Int16.self))
                    peak = max(peak,abs(Int(sample)))
                    if previous <= 0 && sample > 0 { positiveCrossings += 1 }
                    previous = sample
                }
            }
            guard (15000...17500).contains(peak), (200...225).contains(positiveCrossings) else { fatalError("amplitude/frequency changed") }
            print("PASS \(Int(rate))Hz input → 16000Hz mono Int16: \(samples) samples, \(allBytes.count) bytes, peak \(peak), crossings \(positiveCrossings)")
        }
    }
}
