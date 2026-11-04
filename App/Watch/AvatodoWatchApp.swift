import SwiftUI

@main struct AvatodoWatchApp: App {
    @State private var model = WatchModel()
    var body: some Scene { WindowGroup { WatchCompanion(model: model) } }
}
struct WatchCompanion: View {
    @Bindable var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typing = false
    @State private var message = ""
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Button { model.dance() } label: {
                        CompanionArtwork(data: model.characterData, phase: model.state.phase,
                            size: 90, celebrationID: model.state.undoReceiptID, animationLayout: model.characterManifest?.animationLayout,
                            reaction: model.state.reaction, reactionID: model.state.reactionID)
                    }.buttonStyle(.plain).disabled(!model.state.phase.isIdle || reduceMotion)
                        .accessibilityLabel("Make your companion dance")
                        .frame(maxWidth: .infinity)
                    Text(model.state.caption).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineLimit(2).frame(height: 28)
                    ConversationText(text: model.state.text, live: model.state.phase == .listening, compact: true)
                        .padding(8).frame(maxWidth: .infinity)
                        .frame(height: max(0, geometry.size.height - 90 - 28 - 52 - 8), alignment: .top)
                        .background(model.state.text.isEmpty ? Color.clear : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.bottom, 8)
                    ConversationControls(phase: model.state.phase, showUndo: model.showUndo, height: 52,
                        primary: { model.primary() }, undo: { model.undo() })
                        .disabled(!model.canControl)
                }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .padding(.horizontal, 6).padding(.bottom, 8)
            .ignoresSafeArea(.container, edges: .vertical)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Conversation", systemImage: "ellipsis") { typing = true }
                }
            }
            .sheet(isPresented: $typing) {
                List {
                    TextField("Type a message", text: $message)
                    Button("Send") { model.submit(message); message = ""; typing = false }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Start fresh") { model.startFresh(); typing = false }.disabled(!model.state.phase.isIdle)
                    Button("Reconnect") { model.refresh(); typing = false }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .task { model.refresh() }
    }
}
