import SwiftUI
import ImageIO

struct CompanionArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var data: Data?
    var phase: CompanionPhase
    var size: CGFloat
    var celebrationID: UUID?
    @State private var celebrate = false
    @State private var preparedImage: CGImage?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let amplitude = phase == .speaking ? 0.025 : 0.009
            artwork
                .frame(width: size, height: size)
                .scaleEffect(reduceMotion ? 1 : (celebrate ? 1.06 : 1 + sin(t * (phase == .speaking ? 8 : 2)) * amplitude))
                .rotationEffect(.degrees(reduceMotion ? 0 : (celebrate ? -5 : (phase == .listening ? sin(t * 2.5) * 1.2 : 0))))
                .offset(y: reduceMotion ? 0 : (phase == .thinking ? sin(t * 3) * 2 : 0))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your companion")
        .onChange(of: data, initial: true) { _, bytes in
            preparedImage = bytes.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        .task(id: celebrationID) {
            guard celebrationID != nil, !reduceMotion else { return }
            withAnimation(.spring(duration: 0.3)) { celebrate = true }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(duration: 0.4)) { celebrate = false }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let image = preparedImage {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
            Image("DefaultLion").resizable().scaledToFit()
        }
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
