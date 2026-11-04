# Optional Google Drive copies

In Avatodo Settings, choose Google Drive and sign in to your own Google account. Google presents the requested access before connecting. TestFlight users do not need a Google Cloud project or Google API key.

Avatodo creates a visible **Avatodo** folder and uploads a readable Markdown file for each saved note, task or checklist. Later local edits update the same file, including its title and checked items. Uploads run directly from iPhone to Google while the app can run and reach the network. They do not delay the companion's reply. Notes remain usable locally when disconnected or offline.

This is outbound copying, not two-way synchronization. Drive edits are not imported. Deleting a local note or disconnecting does not delete an existing Drive copy; manage those copies in Google Drive. Disconnect signs out on this iPhone and stops uploads. You can separately revoke the app's access in your Google account. Use Upload now after resolving an error; an incomplete upload is not reported as up to date.

The app requests `drive.file` and basic sign-in information. It can access app-created or explicitly selected files, not the whole Drive. Google credentials stay in the iPhone's Google Sign-In Keychain storage. They never go to Meta, Watch or an Avatodo backend. Conversation history, edit receipts and the Meta key are not uploaded. Notes and their stable identifiers/revisions are included in the Markdown copies.

Connecting Muse or another assistant is a separate authorization. The assistant must support reading these actual Markdown files. The Muse reading/demo step is not established by the exporter tests.

## Self-building and forks

The supplied iOS OAuth client identifies the maintainer's `app.avatodo` app and signing team. It is a public native-client identifier, not a secret. If you change the bundle identifier or signing team, create your own iOS OAuth client in Google Cloud, enable the Drive API and configure its consent screen for the narrow scopes above. Set `GIDClientID` and the matching reversed-client-ID URL scheme in `project.yml`, then regenerate the Xcode project. A native client does not require a client secret or hosted backend. Check Google's publication requirements for your own app.

The official Google Sign-In SDK is pinned in the Xcode package resolution. Google manages the sign-in UI, credential storage and refresh. The exporter reserves remote IDs before creates, scopes its local index to the connected account, rejects duplicate/ambiguous targets and validates provider responses without displaying credentials or response bodies.

## Verification boundary

Seven automated export tests cover Markdown content, folder/files without sharing permissions, stable retry IDs, revision skipping, account separation, corrupt/duplicate targets and safe failures. Native iPhone/Watch builds and the real Google sign-in entry/cancel flow have passed in Simulator. Google Cloud shows the app In production and says its requested data scopes do not require sensitive/restricted-scope verification. Real account authorization/upload and Muse read-back still need the owner's account test; no simulator account permission was granted during that entry check.
