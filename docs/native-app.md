# Native app setup

Avatodo contains an iPhone app (`Avatodo`) and paired Watch app (`AvatodoWatch`). The iPhone owns the notes and runs the agent; the Watch needs that paired phone. No Avatodo backend setup or account is required.

## Requirements

- Mac with Xcode 27 and the iOS/watchOS SDKs.
- Deployment targets: iOS 26 and watchOS 26.
- For hardware: a compatible paired iPhone and Apple Watch, appropriate Developer Mode/signing setup, and an Apple signing team selected for both targets.
- Your own direct Meta API access to `muse-spark-1.3` and `muse-image-1.0`. Remote model requests need internet and may incur provider charges.

Exact physical-device behavior is still being verified. Simulator builds do not establish reliable microphone, Watch speaker, background or locked-phone operation.

## Open and build

Open the included `Avatodo.xcodeproj`. It references the local Swift package in this repository and includes the companion Watch target and all required assets. There is no private repository dependency.

Select the **Avatodo** scheme and an iPhone destination. Select **AvatodoWatch** and the paired Watch destination when running/debugging the Watch app. For physical devices, choose your own team for both targets; no team or provisioning profile is shipped as a shared credential.

If Apple signing requires your own bundle identifiers, change both targets consistently: the Watch bundle identifier must use the phone bundle prefix, and `WKCompanionAppBundleIdentifier` must equal the phone app identifier. Update `project.yml` and regenerate when maintaining those settings through XcodeGen. The repository's `app.avatodo` identifiers do not grant signing rights to another team.

For a simulator compile from the repository root:

```sh
xcodebuild -project Avatodo.xcodeproj -scheme Avatodo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData build
```

Keep normal simulator signing enabled when installing and testing Keychain. An unsigned simulator build may compile but fail to save a key. XcodeGen is needed only after changing `project.yml`; run `xcodegen generate` to regenerate the included project. Keep build products in ignored app-owned folders.

## Simulator microphone behavior

Microphone capture is disabled by default in simulator builds, with a graceful message directing you to typed input. The tested iOS 26 simulator runtime aborted inside its CoreAudio microphone service even after an explicit MacBook microphone route was selected; Swift error handling could not recover that host-service abort. Typed companion and paired Watch command testing remain available.

For an intentional audio experiment, set `AVATODO_ENABLE_SIMULATOR_MICROPHONE=1` in the running simulator target's Xcode scheme environment. This opts into a path that has not passed the live voice check on the tested host. The gate is simulator-only; physical-device capture code is unchanged and still requires permission and hardware verification. Do not treat a simulator Listening screen as proof of recorded/transcribed audio.

## Connect your model

1. Open the iPhone app and its **Settings** screen.
2. Enter your own Meta API key and choose **Save key**.
3. The app stores the key in iPhone Keychain. Settings supports replacement/removal without displaying the saved key.
4. Return to the companion and Talk, or choose **Type a message** from the conversation menu.

The Watch never receives the key. A development key saved in macOS Keychain does not automatically synchronize to an iPhone. See [development setup](meta-development-setup.md) for the explicit Debug-simulator-only import helper; physical and release builds do not contain that import route.

## Use the app

The included lion is ready immediately. **Your companion** lets you keep the default or describe a custom companion for Muse Image. The image is prepared and animated locally; custom creation is not yet accepted as an end-to-end native/Watch flow.

The Companion screen supports ordinary conversation and requests to create or change notes. Notes lists your saved notes, tasks and checklists, with manual editing and completion. Open a note and choose **Update this note** for an exact-note interaction in a compact bottom panel. The note stays visible above it.

**Talk** starts capture, **Done** finalizes the utterance, **Cancel** stops outstanding capture/work, and **Stop speaking** stops reply playback. A committed change remains saved when playback stops. After a saved action, temporary Undo shares the bottom control row with Talk; it expires after five seconds or when the next interaction starts. Note-side Undo remains available while the saved revision permits it.

Conversation is temporary: six complete recent exchanges in RAM, separate active-note identity, five-minute idle expiry and **Start fresh** in the conversation menu. Adding twenty items does not stop after the sixth exchange. Starting fresh or restarting the process forgets conversation, not notes.

## Speech and Watch limits

Grant microphone access on the active device and speech-recognition access on iPhone. Recognition runs on the iPhone, on device where supported; some locales may use Apple's speech service. Watch audio relays to iPhone in short sequenced buffers, with partial text sent back for display. Only finalized input can trigger tools.

Recordings are limited to 60 seconds on iPhone and 30 seconds on Watch. Reaching the limit asks for a shorter request rather than saving partial speech automatically. Replies are spoken by the active conversation device with matching captions and a Stop speaking control.

The phone may receive Watch work during a finite background window, but the complete foreground/background/locked/force-quit path needs hardware testing. Keep the apps open during initial development checks. An unavailable phone or delayed reply must not be interpreted as proof that nothing was saved; inspect Notes before repeating a request whose result is uncertain.

## Local data and recovery

The app saves an atomic JSON snapshot under its protected Application Support `Notes/notes.json` folder. The snapshot contains notes, revisions and edit/retry receipts, including before/after note values for safe Undo. Character PNGs and a manifest are cached separately under Application Support `Companion`. Keys are in Keychain. Recorded audio and conversational messages are not saved as an archive.

One `LocalTaskStore` actor owns the notes file. If saved data cannot be opened, the app preserves it and presents an error rather than silently replacing it with an empty notebook. Back up important notes before testing unfinished builds. Key removal, Start fresh and companion changes do not erase notes.

For current test scope and outstanding gates, see [release evidence](release-evidence.md).
