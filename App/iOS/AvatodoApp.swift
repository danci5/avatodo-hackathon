import SwiftUI

@main struct AvatodoApp: App {
    @State private var model = PhoneModel()
    var body: some Scene { WindowGroup { PhoneRoot(model: model) } }
}
