import Foundation
@preconcurrency import AVFoundation

@MainActor final class ReplyAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onEnd: (@MainActor (SpeechPlaybackEnd) -> Void)?
    private var watchdog: Task<Void, Never>?
    private var ownsSession = false
    func play(_ clip: CompletedReplyAudio, ended: @escaping @MainActor (SpeechPlaybackEnd) -> Void) throws {
        stop()
        guard clip.data.count <= ReplyAudioManifest.maximumBytes else { throw ReplyAudioFailure.invalid }
        let player = try AVAudioPlayer(data: clip.data)
        guard player.duration.isFinite, player.duration > 0, player.duration <= 46,
              abs(player.duration - clip.manifest.duration) < 1 else { throw ReplyAudioFailure.invalid }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .default)
            try session.setActive(true); ownsSession = true
            player.delegate = self; self.player = player; onEnd = ended
            guard player.prepareToPlay(), player.play() else { throw ReplyAudioFailure.unavailable }
            let id = ObjectIdentifier(player), start = ProcessInfo.processInfo.systemUptime
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, self.player.map(ObjectIdentifier.init) == id else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    if !player.isPlaying && elapsed > 1 { complete(.finished); return }
                    if elapsed > player.duration + 2 { complete(.unavailable); return }
                }
            }
        } catch { stop(); throw error }
    }
    func stop() {
        watchdog?.cancel(); watchdog = nil; onEnd = nil
        player?.stop(); player = nil
        if ownsSession {
            ownsSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    private func complete(_ outcome: SpeechPlaybackEnd) {
        guard player != nil else { return }
        let callback = onEnd; stop(); callback?(outcome)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finished(ObjectIdentifier(player), outcome: flag ? .finished : .unavailable)
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        finished(ObjectIdentifier(player), outcome: .unavailable)
    }
    nonisolated private func finished(_ id: ObjectIdentifier, outcome: SpeechPlaybackEnd) {
        Task { @MainActor [weak self] in
            guard let self, player.map(ObjectIdentifier.init) == id else { return }
            complete(outcome)
        }
    }
}
