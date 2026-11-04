import SwiftUI
import ImageIO

struct CompanionArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var data: Data?
    var phase: CompanionPhase
    var size: CGFloat
    var celebrationID: UUID?
    var animationLayout: CharacterAnimationLayout? = nil
    var reaction: CompanionReaction? = nil
    var reactionID: UUID? = nil
    var motionEnabled = true
    @State private var preparedFrames: [CGImage] = []
    @State private var player = CompanionMotionPlayer(time: ProcessInfo.processInfo.systemUptime)
    @State private var playedReactionID: UUID?
    @State private var activeReactionID: UUID?
    @State private var reactionTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !motionEnabled || scenePhase != .active)) { _ in
            let sample = player.sample(time: ProcessInfo.processInfo.systemUptime,
                frameCount: preparedFrames.count, reduced: reduceMotion || !motionEnabled)
            artwork(sample.frames)
                .frame(width: size, height: size)
                .scaleEffect(x: sample.scaleX, y: sample.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(sample.rotation), anchor: .bottom)
                .offset(y: sample.lift * size)
                // The motion player owns easing; inherited screen animations must
                // not separately animate every 30 Hz sample.
                .transaction { $0.animation = nil }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore).accessibilityLabel("Your companion")
        .onChange(of: data, initial: true) { _, _ in prepareFrames() }
        .onChange(of: animationLayout) { _, _ in prepareFrames() }
        .onChange(of: phase, initial: true) { _, _ in refreshMotion() }
        .onChange(of: celebrationID) { _, _ in
            if phase == .confirmed {
                player.change(to: .confirmed, time: ProcessInfo.processInfo.systemUptime,
                    frameCount: preparedFrames.count, reduced: reduceMotion, restart: true)
            }
        }
        .onChange(of: reactionID, initial: true) { _, id in
            if id == nil { stopReaction(); playedReactionID = nil }
            refreshMotion()
        }
        .onChange(of: reduceMotion) { _, _ in stopReaction(); refreshMotion() }
        .onAppear { refreshMotion() }
        .onDisappear {
            stopReaction()
            player.change(to: CompanionMotionMode(phase), time: ProcessInfo.processInfo.systemUptime,
                frameCount: preparedFrames.count, reduced: true)
        }
    }
    private func refreshMotion() {
        if !phase.isIdle || phase == .error { stopReaction() }
        let now = ProcessInfo.processInfo.systemUptime
        if motionEnabled, !reduceMotion, phase.isIdle, phase != .error,
           let id = reactionID, let reaction, id != playedReactionID {
            stopReaction(); playedReactionID = id; activeReactionID = id
            player.change(to: reaction == .dance ? .dance : .laugh, time: now, frameCount: preparedFrames.count)
            reactionTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(reaction == .dance ? 3 : 1.8)) } catch { return }
                guard activeReactionID == id else { return }
                activeReactionID = nil; reactionTask = nil
                player.change(to: CompanionMotionMode(phase), time: ProcessInfo.processInfo.systemUptime,
                    frameCount: preparedFrames.count, reduced: reduceMotion)
            }
        } else if activeReactionID == nil {
            player.change(to: CompanionMotionMode(phase), time: now,
                frameCount: preparedFrames.count, reduced: reduceMotion || !motionEnabled)
        }
    }
    private func stopReaction() {
        reactionTask?.cancel(); reactionTask = nil; activeReactionID = nil
    }
    private func prepareFrames() {
        stopReaction()
        let bytes = data ?? Bundle.main.url(forResource: "DefaultLionAtlas", withExtension: "png").flatMap { try? Data(contentsOf: $0) }
        let layout = data == nil && bytes != nil ? CharacterAnimationLayout.twentyPoseV1 : animationLayout
        preparedFrames = bytes.flatMap { try? CharacterAnimationFrames.decode($0, layout: layout) } ?? []
        player = CompanionMotionPlayer(mode: CompanionMotionMode(phase), time: ProcessInfo.processInfo.systemUptime)
    }
    @ViewBuilder private func artwork(_ weights: [CompanionFrameWeight]) -> some View {
        if !preparedFrames.isEmpty {
            Canvas { context, bounds in
                // Add weighted premultiplied colors to avoid darkening the
                // overlapping character halfway through a normal opacity fade.
                context.blendMode = .plusLighter
                for frame in weights where preparedFrames.indices.contains(frame.index) {
                    let image = preparedFrames[frame.index]
                    let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
                    let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
                    context.opacity = frame.opacity
                    context.draw(Image(decorative: image, scale: 1).interpolation(.high),
                        in: CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height))
                }
            }.accessibilityHidden(true)
        } else { Image("DefaultLion").resizable().scaledToFit() }
    }
}

struct ConversationControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phase: CompanionPhase
    var showUndo = false
    var height: CGFloat = 56
    let primary: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: primary) {
                Text(phase.actionTitle)
                    .font(.body.weight(phase.isIdle ? .semibold : .regular))
                    .foregroundStyle(primaryColor)
                    .contentTransition(.opacity).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .modifier(ActionSurface(emphasized: phase.isIdle))
            if showUndo && phase.isIdle {
                Button(action: undo) {
                    Text("Undo").font(.body).foregroundStyle(.primary).frame(maxWidth: .infinity)
                }
                .modifier(ActionSurface(emphasized: false))
                .accessibilityLabel("Undo last saved change")
                .transition(.opacity)
            }
        }
        .controlSize(.large).buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity).frame(height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: showUndo)
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: phase)
    }
    private var primaryColor: Color {
        #if os(iOS)
        phase.isIdle ? .white : .primary
        #else
        phase.isIdle ? .white : .primary
        #endif
    }
}

private struct ActionSurface: ViewModifier {
    let emphasized: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content.buttonStyle(.glassProminent)
            .tint(emphasized ? .blue : Color(.systemGray4))
            .overlay { Capsule().strokeBorder(Color.primary.opacity(emphasized ? 0 : 0.12), lineWidth: 1).allowsHitTesting(false) }
        #else
        content.buttonStyle(.glass).tint(emphasized ? Color.blue.opacity(0.35) : Color.gray.opacity(0.12))
        #endif
    }
}

struct ConversationText: View {
    let text: String
    var live = false
    var compact = false
    @State private var followsLatest = true
    @State private var userScrolling = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 1).id("start")
                    Text(text.isEmpty && live ? "Start speaking…" : text)
                        .font(compact ? .callout : .body)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(ConversationSelection())
                    Color.clear.frame(height: 1).id("latest")
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 12
            } action: { _, atBottom in
                if userScrolling { followsLatest = atBottom }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { userScrolling = true }
                else if phase == .idle { userScrolling = false }
            }
            .onChange(of: text) { _, _ in
                if live && followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
                else if !live { proxy.scrollTo("start", anchor: .top) }
            }
            .onChange(of: live) { _, _ in
                followsLatest = true
                proxy.scrollTo(live ? "latest" : "start", anchor: live ? .bottom : .top)
            }
            .overlay(alignment: .bottomTrailing) {
                if live && !followsLatest {
                    Button("Latest", systemImage: "arrow.down") {
                        followsLatest = true; proxy.scrollTo("latest", anchor: .bottom)
                    }.font(.caption2).buttonStyle(.glass).controlSize(.mini)
                }
            }
        }
    }
}

private struct ConversationSelection: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.textSelection(.enabled)
        #else
        content
        #endif
    }
}
