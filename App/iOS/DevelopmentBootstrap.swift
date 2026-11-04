#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Opt-in simulator convenience. This code is absent from release and physical-device builds.
/// The launcher passes a key through child-process memory; it is saved only in simulator Keychain.
enum DevelopmentBootstrap {
    static func importKeyIfProvided() throws {
        guard let value = ProcessInfo.processInfo.environment["AVATODO_DEVELOPMENT_META_KEY"] else { return }
        defer { unsetenv("AVATODO_DEVELOPMENT_META_KEY") }
        try KeychainStore.save(value)
    }
}
#endif
