import Foundation

/// Versioned, local permission for remote model requests. No credential is stored here.
@MainActor final class MetaDataSharingConsent {
    private static let key = "metaDataSharingConsent.v1"
    private let defaults: UserDefaults
    private(set) var isGranted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isGranted = defaults.bool(forKey: Self.key)
    }
    func setGranted(_ allowed: Bool) {
        isGranted = allowed
        defaults.set(allowed, forKey: Self.key)
    }
    func requirePermission() throws {
        guard isGranted else { throw MetaConsentError.permissionRequired }
    }
}

enum MetaConsentError: Error, LocalizedError {
    case permissionRequired, revoked
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "Review data sharing and allow Meta requests in Avatodo’s iPhone Settings first. You can still use Notes without Meta."
        case .revoked: "Meta requests are off. Any changes already saved remain in Notes."
        }
    }
}
