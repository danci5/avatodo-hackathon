import Foundation
@preconcurrency import AVFoundation

/// Converter state stays inside this synchronous audio callback helper. The lock also
/// protects it if the audio engine changes its callback thread between buffers.
final class RelayPCMEncoder: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()
    init?(inputFormat: AVAudioFormat) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                        channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else { return nil }
        self.converter = converter; self.outputFormat = output
    }
    func encode(_ input: AVAudioPCMBuffer) -> Data? {
        lock.lock(); defer { lock.unlock() }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return input
        }
        guard status != .error, error == nil, let channel = output.int16ChannelData?[0] else { return nil }
        // Apple platforms use little-endian PCM. 16k mono Int16 is 32 KB/s.
        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}
