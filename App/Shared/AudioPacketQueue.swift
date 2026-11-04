import Foundation

enum AudioPacketFailure: Error, Equatable, Sendable {
    case conversion, overflow
}

/// A capture owns one queue. Closing it atomically drains every accepted packet;
/// late callbacks cannot add audio to that capture or to its successor.
final class AudioPacketQueue: @unchecked Sendable {
    struct Batch: Sendable {
        let packets: [Data]
        let failure: AudioPacketFailure?
    }
    private let lock = NSLock()
    private let byteLimit: Int
    private let packetLimit: Int
    private var open = true
    private var packets: [Data] = []
    private var bytes = 0
    private var failure: AudioPacketFailure?
    private var deliveryScheduled = false

    init(byteLimit: Int = 256_000, packetLimit: Int = 128) {
        self.byteLimit = byteLimit; self.packetLimit = packetLimit
    }

    /// Returns true only when the producer must schedule a delivery task.
    func append(_ packet: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return appendLocked(packet)
    }

    /// Closing waits for a conversion that already entered this capture. The
    /// callback never schedules tasks or delivers data while holding this lock.
    func encodeAndAppend(_ encode: () -> Data?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard open, failure == nil else { return false }
        guard let packet = encode() else {
            failure = .conversion; packets.removeAll(); bytes = 0
            return scheduleDelivery()
        }
        return appendLocked(packet)
    }

    private func appendLocked(_ packet: Data) -> Bool {
        guard open, failure == nil, !packet.isEmpty else { return false }
        guard packet.count <= 32_768, packet.count.isMultiple(of: 2) else {
            failure = .conversion; packets.removeAll(); bytes = 0; return scheduleDelivery()
        }
        guard packets.count < packetLimit, packet.count <= byteLimit - bytes else {
            failure = .overflow; packets.removeAll(); bytes = 0; return scheduleDelivery()
        }
        packets.append(packet); bytes += packet.count
        return scheduleDelivery()
    }

    func conversionFailed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard open else { return false }
        failure = .conversion; packets.removeAll(); bytes = 0
        return scheduleDelivery()
    }

    private func scheduleDelivery() -> Bool {
        guard !deliveryScheduled else { return false }
        deliveryScheduled = true
        return true
    }

    func drain(closing: Bool = false) -> Batch {
        lock.lock(); defer { lock.unlock() }
        if closing { open = false }
        let result = Batch(packets: packets, failure: failure)
        packets.removeAll(keepingCapacity: !closing); bytes = 0; deliveryScheduled = false
        return result
    }

    func discard() {
        lock.lock(); defer { lock.unlock() }
        open = false; packets.removeAll(); bytes = 0; deliveryScheduled = false
    }
}
