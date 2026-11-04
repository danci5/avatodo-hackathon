#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_folder=$(mktemp -d "${TMPDIR:-/tmp}/avatodo-consent.XXXXXX")
trap 'rm -rf "$check_folder"' EXIT
cat > "$check_folder/ConsentCheck.swift" <<'SWIFT'
import Foundation

@main struct ConsentCheck {
    @MainActor static func main() throws {
        let suite = "app.avatodo.consent-check." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Test preferences unavailable") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let permission = MetaDataSharingConsent(defaults: defaults)
        precondition(!permission.isGranted)
        var requests = 0
        func boundary() throws { try permission.requirePermission(); requests += 1 }
        do { try boundary(); fatalError("Unapproved request passed") } catch is MetaConsentError {}
        precondition(requests == 0)
        permission.setGranted(true)
        try boundary()
        precondition(requests == 1 && MetaDataSharingConsent(defaults: defaults).isGranted)
        permission.setGranted(false)
        do { try boundary(); fatalError("Revoked request passed") } catch is MetaConsentError {}
        precondition(requests == 1 && !MetaDataSharingConsent(defaults: defaults).isGranted)
        var state = CompanionViewState()
        state.hasDataSharingConsent = true
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CompanionViewState.self, from: encoded)
        precondition(decoded.hasDataSharingConsent == true)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "hasDataSharingConsent")
        let missingPermission = try JSONDecoder().decode(CompanionViewState.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(missingPermission.hasDataSharingConsent != true)
        print("PASS: default deny, explicit allow, persisted grant/revoke, denied side effects, wire round-trip and missing wire permission. No model requests sent.")
    }
}
SWIFT
swiftc App/Shared/CompanionState.swift App/iOS/MetaDataSharingConsent.swift "$check_folder/ConsentCheck.swift" -o "$check_folder/check"
"$check_folder/check"
