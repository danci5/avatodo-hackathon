import Foundation

@main enum CompanionMotionChecks {
    static func main() {
        for count in [1, 9, 16, 20] {
            for mode in [CompanionMotionMode.ready, .listening, .thinking, .speaking, .confirmed, .error, .dance, .laugh] {
                let player = CompanionMotionPlayer(mode: mode, time: 10)
                for step in 0..<360 {
                    let sample = player.sample(time: 10 + Double(step) / 30, frameCount: count)
                    precondition(!sample.frames.isEmpty && sample.frames.count <= 8)
                    precondition(sample.frames.allSatisfy { (0..<count).contains($0.index) && $0.opacity > 0 && $0.opacity <= 1 })
                    precondition(abs(sample.frames.reduce(0) { $0 + $1.opacity } - 1) < 0.00001)
                    precondition([sample.scaleX, sample.scaleY, sample.rotation, sample.lift].allSatisfy(\.isFinite))
                    precondition(abs(sample.rotation) <= 4 && abs(sample.lift) <= 0.03)
                }
            }
        }
        print("PASS all states and loops stay in atlas bounds with normalized, bounded compositing")

        var player = CompanionMotionPlayer(time: 10)
        let before = player.sample(time: 11, frameCount: 20)
        player.change(to: .listening, time: 11, frameCount: 20)
        let start = player.sample(time: 11, frameCount: 20)
        precondition(start.frames == before.frames && start.rotation == before.rotation && start.scaleY == before.scaleY)
        let middle = player.sample(time: 11.12, frameCount: 20)
        precondition(middle.frames.contains { $0.index == 0 } && middle.frames.contains { $0.index == 1 })
        player.change(to: .thinking, time: 11.12, frameCount: 20)
        let interrupted = player.sample(time: 11.12, frameCount: 20)
        precondition(interrupted.frames == middle.frames && interrupted.rotation == middle.rotation)
        let end = player.sample(time: 11.4, frameCount: 20)
        precondition(end.frames == [.init(index: 2, opacity: 1)])
        print("PASS state changes ease from the visible frame; interrupted fades do not restart with a cut")

        let reduced = CompanionMotionPlayer(mode: .dance, time: 10)
        let one = reduced.sample(time: 11, frameCount: 20, reduced: true)
        let two = reduced.sample(time: 20, frameCount: 20, reduced: true)
        precondition(one.frames == two.frames && one.scaleX == 1 && one.scaleY == 1 && one.rotation == 0 && one.lift == 0)
        let speaking = CompanionMotionPlayer(mode: .speaking, time: 0)
        for t in stride(from: 0.12, to: 0.14, by: 0.001) {
            let sample = speaking.sample(time: t, frameCount: 20)
            precondition(sample.frames.count == 2)
        }
        print("PASS Reduce Motion is static and adjacent speaking frames blend locally without inference")
    }
}
