import Foundation

enum CompanionMotionMode: Equatable {
    case ready, listening, thinking, speaking, confirmed, error, dance, laugh
    init(_ phase: CompanionPhase) {
        switch phase {
        case .ready: self = .ready
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .speaking: self = .speaking
        case .confirmed: self = .confirmed
        case .error: self = .error
        }
    }
}

struct CompanionFrameWeight: Equatable { var index: Int; var opacity: Double }
struct CompanionMotionSample {
    var frames: [CompanionFrameWeight]
    var scaleX = 1.0
    var scaleY = 1.0
    var rotation = 0.0
    /// Relative to the artwork's fixed size, so phone and Watch share motion.
    var lift = 0.0
}

/// Pure local timing. State changes blend the actually visible frame/movement,
/// including an interrupted transition, instead of jumping to a new pose.
struct CompanionMotionPlayer {
    static let transitionDuration = 0.24
    private(set) var mode: CompanionMotionMode
    private var began: TimeInterval
    private var previous: CompanionMotionSample?

    init(mode: CompanionMotionMode = .ready, time: TimeInterval) { self.mode = mode; began = time }

    mutating func change(to next: CompanionMotionMode, time: TimeInterval, frameCount: Int, reduced: Bool = false, restart: Bool = false) {
        guard next != mode || restart else { return }
        let visible = sample(time: time, frameCount: frameCount, reduced: reduced)
        previous = reduced ? nil : visible
        mode = next; began = time
    }

    func sample(time: TimeInterval, frameCount: Int, reduced: Bool = false) -> CompanionMotionSample {
        let age = max(0, time - began)
        let target = target(time: time, age: age, frameCount: frameCount, reduced: reduced)
        guard !reduced, let previous, age < Self.transitionDuration else { return target }
        let p = Self.ease(age / Self.transitionDuration)
        return CompanionMotionSample(frames: Self.combine(previous.frames, target.frames, progress: p),
            scaleX: previous.scaleX + (target.scaleX - previous.scaleX) * p,
            scaleY: previous.scaleY + (target.scaleY - previous.scaleY) * p,
            rotation: previous.rotation + (target.rotation - previous.rotation) * p,
            lift: previous.lift + (target.lift - previous.lift) * p)
    }

    private func target(time: TimeInterval, age: TimeInterval, frameCount: Int, reduced: Bool) -> CompanionMotionSample {
        let modern = frameCount == 20, sixteen = frameCount == 16, nine = frameCount == 9
        func still(_ index: Int) -> [CompanionFrameWeight] {
            [.init(index: (modern || sixteen || nine) ? index : 0, opacity: 1)]
        }
        let frames: [CompanionFrameWeight]
        switch mode {
        case .ready:
            let blink = time.truncatingRemainder(dividingBy: 5.4)
            if !reduced, (modern || sixteen), blink > 5.12 {
                let p = (blink - 5.12) / 0.28
                let closed = p < 0.35 ? Self.ease(p / 0.35) : p > 0.65 ? Self.ease((1 - p) / 0.35) : 1
                frames = Self.combine(still(0), still(3), progress: closed)
            } else { frames = still(0) }
        case .listening: frames = still(1)
        case .thinking: frames = still(2)
        case .error: frames = still(0)
        case .confirmed: frames = still(modern ? 4 : 0)
        case .speaking:
            frames = reduced ? still(modern ? 5 : sixteen ? 4 : 3) :
                Self.loop(modern ? [5, 6, 7, 8, 9] : sixteen ? [4, 6, 4, 7] : nine ? [3, 4, 3, 5] : [0], age: age, fps: 7)
        case .dance:
            frames = reduced ? still(0) : Self.loop(modern ? Array(10...14) : sixteen ? [8, 9, 10, 11] : nine ? [6, 7] : [0], age: age, fps: modern ? 5 : 4)
        case .laugh:
            frames = reduced ? still(0) : Self.loop(modern ? [15, 16, 17, 18, 19] : sixteen ? [12, 13, 14, 13, 15] : nine ? [8] : [0], age: age, fps: 5)
        }
        guard !reduced else { return CompanionMotionSample(frames: frames) }
        let breathing = sin(time * 2)
        var sample = CompanionMotionSample(frames: frames, scaleX: 1 + breathing * 0.009, scaleY: 1 + breathing * 0.014)
        switch mode {
        case .listening: sample.rotation = -1.8 + sin(time * 1.6) * 0.6
        case .thinking: sample.rotation = sin(time * 1.4) * 1.2
        case .speaking: sample.scaleY += sin(age * 8) * 0.006
        case .confirmed:
            sample.lift = age < 0.7 ? -sin(age / 0.7 * .pi) * 0.018 : 0
        case .dance:
            let entry = Self.ease(min(1, age / 0.3))
            sample.rotation = sin(age * .pi * 3.2) * 3.5 * entry
            sample.lift = -abs(sin(age * .pi * 3.2)) * 0.018 * entry
        case .laugh:
            sample.rotation = sin(age * 17) * 0.8
            sample.scaleY += sin(age * 17) * 0.008
        case .ready, .error: break
        }
        return sample
    }

    private static func loop(_ sequence: [Int], age: TimeInterval, fps: Double) -> [CompanionFrameWeight] {
        let position = max(0, age) * fps
        let step = Int(position.truncatingRemainder(dividingBy: Double(sequence.count)))
        let fraction = position - floor(position)
        // A brief dissolve between neighboring in-betweens softens texture cuts;
        // this is not optical-flow interpolation or a 3D skeleton.
        let p = ease(max(0, (fraction - 0.7) / 0.3))
        return combine([.init(index: sequence[step], opacity: 1)],
            [.init(index: sequence[(step + 1) % sequence.count], opacity: 1)], progress: p)
    }

    private static func ease(_ value: Double) -> Double {
        let p = min(1, max(0, value)); return p * p * (3 - 2 * p)
    }
    private static func combine(_ a: [CompanionFrameWeight], _ b: [CompanionFrameWeight], progress: Double) -> [CompanionFrameWeight] {
        var weights: [Int: Double] = [:]
        for frame in a { weights[frame.index, default: 0] += frame.opacity * (1 - progress) }
        for frame in b { weights[frame.index, default: 0] += frame.opacity * progress }
        // Bound compositing work even if a burst of state updates interrupts fades.
        let retained = weights.filter { $0.value > 0.00001 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(8)
        let total = retained.reduce(0) { $0 + $1.value }
        return retained.map { .init(index: $0.key, opacity: $0.value / total) }.sorted { $0.index < $1.index }
    }
}
