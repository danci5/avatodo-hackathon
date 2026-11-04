import Foundation

private final class RecordedAudioBatch: @unchecked Sendable {
    private let lock = NSLock()
    private var batch: AudioPacketQueue.Batch?
    func store(_ value: AudioPacketQueue.Batch) { lock.lock(); batch = value; lock.unlock() }
    func load() -> AudioPacketQueue.Batch? { lock.lock(); defer { lock.unlock() }; return batch }
}

@main enum AudioQueueChecks {
    static func packet(_ value: UInt16) -> Data {
        var sample = value.littleEndian
        return withUnsafeBytes(of: &sample) { Data($0) }
    }
    static func main() {
        let queue = AudioPacketQueue()
        var deliveries = 0
        for value in 0..<100 { if queue.append(packet(UInt16(value))) { deliveries += 1 } }
        let tail = queue.drain(closing: true)
        precondition(deliveries == 1 && tail.failure == nil && tail.packets == (0..<100).map { packet(UInt16($0)) })
        precondition(!queue.append(packet(100)) && queue.drain().packets.isEmpty)
        print("PASS: one coalesced delivery, ordered accepted tail drained at close, late packets rejected")

        let limited = AudioPacketQueue(byteLimit: 4, packetLimit: 10)
        _ = limited.append(packet(1)); _ = limited.append(packet(2)); _ = limited.append(packet(3))
        let overflow = limited.drain(closing: true)
        precondition(overflow.failure == .overflow && overflow.packets.isEmpty)
        let packetLimited = AudioPacketQueue(byteLimit: 100, packetLimit: 1)
        _ = packetLimited.append(packet(1)); _ = packetLimited.append(packet(2))
        precondition(packetLimited.drain().failure == .overflow)
        print("PASS: byte/packet overflow fails closed without delivering a truncated batch")

        let conversion = AudioPacketQueue()
        _ = conversion.append(packet(1)); _ = conversion.conversionFailed()
        precondition(conversion.drain().failure == .conversion && conversion.drain().packets.isEmpty)
        let malformed = AudioPacketQueue(); _ = malformed.append(Data([1]))
        precondition(malformed.drain().failure == .conversion)
        print("PASS: conversion and malformed PCM fail closed")

        let cancelled = AudioPacketQueue(); _ = cancelled.append(packet(1)); cancelled.discard()
        precondition(!cancelled.append(packet(2)) && cancelled.drain().packets.isEmpty)
        let next = AudioPacketQueue(); precondition(next.append(packet(3)))
        precondition(next.drain().packets == [packet(3)])
        print("PASS: cancellation discards pending audio without contaminating the next capture")

        let concurrent = AudioPacketQueue(byteLimit: 10_000, packetLimit: 1000)
        for value in 0..<20 { _ = concurrent.append(packet(UInt16(value))) }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            for value in 20..<500 { _ = concurrent.append(packet(UInt16(value))) }
            group.leave()
        }
        let closed = concurrent.drain(closing: true)
        group.wait()
        precondition(closed.failure == nil && closed.packets.count >= 20)
        precondition(closed.packets == (0..<closed.packets.count).map { packet(UInt16($0)) })
        precondition(concurrent.drain().packets.isEmpty)
        print("PASS: concurrent producer/close has a single ordered accepted-packet boundary")

        let converting = AudioPacketQueue()
        let enteredConversion = DispatchSemaphore(value: 0)
        let releaseConversion = DispatchSemaphore(value: 0)
        let closeStarted = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)
        let captured = RecordedAudioBatch()
        DispatchQueue.global().async {
            _ = converting.encodeAndAppend {
                enteredConversion.signal()
                precondition(releaseConversion.wait(timeout: .now() + 2) == .success)
                return packet(91)
            }
        }
        precondition(enteredConversion.wait(timeout: .now() + 2) == .success)
        DispatchQueue.global().async {
            closeStarted.signal()
            captured.store(converting.drain(closing: true))
            closeFinished.signal()
        }
        precondition(closeStarted.wait(timeout: .now() + 2) == .success)
        precondition(closeFinished.wait(timeout: .now() + .milliseconds(30)) == .timedOut)
        releaseConversion.signal()
        precondition(closeFinished.wait(timeout: .now() + 2) == .success)
        precondition(captured.load()?.packets == [packet(91)] && captured.load()?.failure == nil)
        precondition(!converting.encodeAndAppend { preconditionFailure("Closed capture must not run a late converter") })
        print("PASS: close waits for in-flight conversion and drains its packet before finalization")
    }
}
