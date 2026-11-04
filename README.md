# Avatodo

A personalized companion for iPhone and Apple Watch, demonstrated with a local notes and checklist agent.

The iPhone runs the agent, stores your notes and calls Meta directly with **your own API key**. There is no Avatodo-hosted backend, shared developer key or mandatory account.

**Development status:** native iPhone and Watch targets build and run in paired simulators. Actual Meta calls have created notes, corrected and completed checklist items, and generated a custom companion that appears on both devices. Typed Watch requests reach the iPhone agent and local store. The complete microphone → Watch → saved-note flow and physical-device reliability are still being verified. TestFlight build **0.1.0 (2)** has processed, and the owner reports it is installed and opens on iPhone. The first phone Talk/Done attempt ended with a Meta authentication/access error; a development-signed build 3 is installed on phone for diagnosis, but its new connection check has not been exercised there. The complete saved-result voice flow remains pending. There is no public beta approval, public testing link or App Store release. See [release evidence](docs/release-evidence.md) for the limits of each result.

## The companion

Use the included stylized 3D lion, or describe a companion for Muse Image to create. The iPhone prepares the image locally and transfers the same character to Watch. Gentle SwiftUI motion responds to listening, thinking, speaking and saved changes; this is local animation from artwork, not generated video.

Talk or type to the companion to create and update notes, tasks and checklists. Notes also support manual editing and checking off items. **Update this note** opens a compact companion panel scoped to that exact note. Ordinary conversation does not create a note.

Conversation stays in memory, with a five-minute idle timeout and a Start fresh action. Notes and operational edit/Undo receipts are saved locally; there is no saved chat archive.

## Build and run

The repository is temporarily private during submission preparation. Public visibility and logged-out access must be verified before the hackathon entry.

Building from source requires a Mac with Xcode 27, the iOS/watchOS SDKs and your own Meta access to `muse-spark-1.3` and `muse-image-1.0`. The app deployment targets are iOS 26 and watchOS 26. Development installation from Xcode also needs Apple signing and a compatible paired iPhone/Watch. Invited TestFlight installation is a separate route and does not require Developer Mode; see [native app setup](docs/native-app.md#internal-testflight-checkpoint).

```sh
git clone https://github.com/danci5/avatodo-hackathon.git
cd avatodo-hackathon
open Avatodo.xcodeproj
```

Select the **Avatodo** scheme and an iPhone destination. For hardware, choose your signing team for both targets, then run the phone and companion Watch apps. In the iPhone app, open **Settings**, enter your own Meta API key and save it in iPhone Keychain. No backend setup is required. Cloning the repository does not install a Watch app automatically.

The generated Xcode project and all required artwork are included. XcodeGen is needed only to regenerate the project after changing `project.yml`; no separate private repository is required. See [native app setup and behavior](docs/native-app.md) for simulator, speech and device details.

## Development checks

```sh
bash scripts/test.sh
zsh scripts/check-audio-relay.sh
zsh scripts/check-character-transfer.sh
zsh scripts/check-meta-consent.sh
```

These local checks need no API key. An explicit live check, `swift run AvatodoProbe --run-live`, sends billable requests with fictional notes; see [secure Meta development setup](docs/meta-development-setup.md) first.

- [Architecture](docs/architecture.md)
- [Local task engine and agent](docs/local-task-engine.md)
- [Shared Swift live Meta evidence](docs/shared-swift-live-evidence.md)
- [Contributing](CONTRIBUTING.md)

## Privacy and licensing

Meta features require users aged **18 or older**, their own legitimate provider access, and explicit permission in **Settings → Data sharing with Meta**. Build 2 resets earlier permission so the updated notice must be reviewed.

Remote reasoning and image generation require internet and provider access. Relevant text, note context and character descriptions are sent to Meta. Speech uses Apple recognition on the iPhone, on device where supported; some locales may use Apple's speech service. Watch audio is relayed to the paired iPhone and is not saved by Avatodo. Replies are spoken on the device where the conversation began.

Keys stay in iPhone Keychain and never travel to Watch. Local notes and animation do not imply offline model inference or zero retention by providers. API usage charges may apply. The app declares model-bound text/notes/prompts as Other User Content for App Functionality, linked to the provider account and not used by Avatodo for tracking. Local conversation expiry does not promise deletion of content retained by Meta. Do not share a provider key with reviewers without Meta’s required permission; see the [review access gate](docs/release-evidence.md#external-review-access-gate).

Source is licensed under [Apache-2.0](LICENSE). Provider services, models and generated assets retain their applicable terms; bundled artwork provenance is recorded in [the asset manifest](App/Resources/asset-provenance.json). No affiliation with Apple, Meta or Ray-Ban is implied.
