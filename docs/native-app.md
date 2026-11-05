# Native app setup

Avatodo contains an iPhone app (`Avatodo`) and paired Watch app (`AvatodoWatch`). The iPhone owns the notes and runs the agent; the Watch needs that paired phone. No Avatodo backend setup or account is required.

## Requirements

- To build from source: a Mac with Xcode 27 and the iOS/watchOS SDKs.
- Deployment targets: iOS 26 and watchOS 26.
- For Xcode development installation: a compatible paired iPhone and Apple Watch, appropriate Developer Mode/signing setup, and an Apple signing team selected for both targets. TestFlight installation uses the separate route below.
- Age 18 or older for Meta features, as required by the provider, plus affirmative in-app data-sharing permission.
- Your own direct Meta API access to `muse-spark-1.3` (or optional `muse-wonder-1.0`) and `muse-image-1.0`. Remote model requests need internet and may incur provider charges.

Exact physical-device behavior is still being verified. Simulator builds do not establish reliable microphone, Watch speaker, background or locked-phone operation.

## Current TestFlight status, 5 November

Build **0.1.0 (9)** uploaded successfully at 00:25:35 CET with optional Drive Markdown/plain-text formats, corrected voice-preview order and the Talk/Done startup fix. App Store Connect confirms **Ready to Submit**, a 90-day window, assignment to Avatodo Internal's one invited owner, and saved/reloaded instructions. Update through TestFlight to build **0.1.0 (9)**. External review/public installation remains pending. Later owner reports confirm Watch speaker replies and a real personal Drive Markdown upload; full physical acceptance of build 9, TXT preview and Muse access are still pending.

## Historical build-5 TestFlight checkpoint

On 4 November 2026, App Store Connect showed voice-personalization build **0.1.0 (5)** fully processed with status **Ready to Submit**, a 90-day testing window and association with the internal group’s one invited owner. Its clean archive, App Store distribution export and upload all succeeded, and What to Test was saved. Build 5 installation and Watch installation have not been confirmed. An external group exists but has no builds or testers, no Beta Review submission and no public testing link. This is not public beta or App Store approval.

Use TestFlight to update the iPhone to Avatodo **0.1.0 (5)**, then the iPhone Watch app’s **Show App on Apple Watch** control to install its companion. A previous attempt stalled. A temporary development-signed phone update contained a Watch development profile without the paired Watch’s identifier; that may have interfered, but the cause is not confirmed. Exported App Store profiles for builds 3, 4 and 5 are verified to have no device restrictions. Cancel the stalled attempt before retrying through the TestFlight distribution route. No further development install is part of this recovery. Watch installation remains unconfirmed.

The owner first reported phone Check connection returning HTTP 401. After **Copy Password to Clipboard** in Mac Keychain and pasting on the actual iPhone, the owner reported both required models listed, then confirmed that a typed request produced a reply. Those are user-reported catalog and typed-inference passes. The owner then reported empty Listening and Talk/Done failure, followed by successful live words and a reply after stopping the Mac connection; Voice Memos reportedly recovered too. The installed build/version was not confirmed, so that user report is not attributed to build 4 or 5. A complete voice-to-saved-note action, chosen-voice playback and the physical Watch flow remain unconfirmed. Source/build checks do not establish those hardware results.

Developer Mode is for development workflows such as running from Xcode; Apple states that it is not required for TestFlight installation. See [Apple’s Developer Mode guidance](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/). The owner reported Watch Developer Mode enabled, but the Mac connection did not confirm its current state; this does not establish a TestFlight installation blocker.

## Open and build

Open the included `Avatodo.xcodeproj`. It references the local Swift package in this repository and includes the companion Watch target and all required assets.

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
4. Review **Data sharing with Meta**, including its 18+ requirement, and choose **Allow Meta requests**. This starts off; adding a key alone does not grant permission. Build 2 uses a new consent version, so an earlier build’s grant does not bypass the updated notice.
5. In build 3, choose **Check connection**. It sends only a catalog-authentication request, without notes or inference. A key being stored does not establish access, and listed models do not establish successful inference.
6. Return to the companion and Talk, or choose **Type a message** from the conversation menu.

Permission covers both phone and Watch requests. Meta receives messages/transcriptions, temporary recent conversation and note context (including note titles/details and notes read or updated by the agent); companion creation sends its description to Muse Image. Raw Watch audio relays to iPhone for Apple speech recognition, not to Meta. **Turn off Meta requests** in Settings revokes permission and cancels outstanding model work. Already committed note changes remain saved. Manual Notes editing and the default companion remain usable without model permission. The local five-minute conversation expiry does not control Meta’s retention of content already sent. For reviewer access, follow the [external-review gate](release-evidence.md#external-review-access-gate); never assume a private key can be shared with Apple or another tester.

The Watch never receives the key. A development key saved in macOS Keychain does not automatically synchronize to an iPhone. To copy your own saved key, use **Keychain Access → Copy Password to Clipboard**, then paste directly into the secure field on the actual iPhone; generic Copy can copy the entry name, and Show Password is not required. See the [copy instructions](meta-development-setup.md#copying-your-own-development-key-to-iphone), including Universal Clipboard requirements. A successful connection check must be followed by a separate Talk/Done test; it authenticates the catalog without testing inference or voice. See [development setup](meta-development-setup.md) for the explicit Debug-simulator-only import helper; physical and release builds do not contain that import route.

## Use the app

The included lion is ready immediately. **Your companion** lets you keep the default or describe a custom companion for Muse Image. The image is prepared and animated locally. Real in-app creation and matching artwork on both paired simulators have been verified; physical-device creation/transfer remains to be tested.

The Companion screen supports ordinary conversation and requests to create or change notes. Notes lists your saved notes, tasks and checklists, with manual editing and completion. Open a note and choose **Update this note** for an exact-note interaction in a compact bottom panel. The note stays visible above it.

**Talk** starts capture, **Done** finalizes the utterance, **Cancel** stops outstanding capture/work, and **Stop speaking** stops reply playback. A committed change remains saved when playback stops. After a saved action, temporary Undo shares the bottom control row with Talk; it expires after five seconds or when the next interaction starts. Note-side Undo remains available while the saved revision permits it.

Conversation is temporary: six complete recent exchanges in RAM, separate active-note identity, five-minute idle expiry and **Start fresh** in the conversation menu. Adding twenty items does not stop after the sixth exchange. Starting fresh or restarting the process forgets conversation, not notes.

## Choose your companion’s reply voice

1. On iPhone, open **Settings → Accessibility → Read & Speak → Voices → your language**. Download an available **Enhanced** or **Premium** voice and wait for the download to finish.
2. Return to **Avatodo Settings → Voice → Reply voice** and select that voice by name. Quality and human-readable language/dialect labels distinguish the installed options.
3. Choose **Preview voice** to hear a short local sample; **Stop preview** ends it. Preview is available while the companion is idle and sends no model request. The choice is saved on this iPhone.

**Automatic** chooses a high-quality available voice for the current language. It does not mean follow the selected Siri voice or Accessibility voice. Apple’s [speech-synthesis session](https://developer.apple.com/videos/play/wwdc2020/10022/) explains that Siri voices are not exposed through this API; selecting or downloading a Siri voice in system Settings does not make it an Avatodo option. Personal Voice is not included.

The Watch receives the preferred voice identifier and language. It uses that voice if installed locally, otherwise a matching installed voice chosen by quality. iPhone and Watch voice inventories can differ; a phone download does not establish Watch availability. The preference is not stored in Watch UserDefaults.

Simulator checks verified voice options, selection persistence through relaunch, and Preview/Stop/end behavior. The owner confirmed that a downloaded voice appears and previews on physical iPhone in TestFlight build 5. Watch speaker playback was subsequently reported working with a simpler local fallback voice; the selected iPhone Premium voice has not been confirmed available on Watch.

In build 6, playback has bounded recovery when Apple never starts speech, stops reporting progress or omits its completion callback. An interrupted or unavailable voice leaves the reply text and saved changes intact and returns the main control to Talk. Stopping speech never undoes a committed note change. For local Watch speech, Apple’s managed speech session uses installed Watch voices. Build 7 also offers iPhone-generated audio delivery, described below; the iPhone voice pack stays on iPhone. Apple describes Watch voice downloads under [Settings → Accessibility → Live Speech → Voices](https://support.apple.com/guide/watch/type-to-speak-apd86a007717/watchos); availability through the app's speech API still depends on the Watch's installed voices.

## Saved companions

Build 6 keeps Ava plus the three most recent generated companions on this iPhone. The gallery preserves artwork, name and description, and selecting an older companion does not reorder creation history. The selected character is sent to the paired Watch. Creating a fourth custom companion replaces the oldest gallery entry. Character drafts survive dismissing the editor and app relaunch. Older builds saved only the current character's name and no descriptions; migration recovers available cached artwork as “Saved companion” without inventing lost names or prompts.

The current companion's name is included in each Meta agent turn as app context, so changing companions also changes the identity provided to the model. Empty recordings quietly return to Talk without making a model request; partial speech or genuine service failures cannot authorize a note action.

## Speech and Watch limits

Grant microphone access on the active device and speech-recognition access on iPhone. Recognition runs on the iPhone, on device where supported; some locales may use Apple's speech service. Watch audio relays to iPhone in short sequenced buffers, with partial text sent back for display. Only finalized input can trigger tools.

Build 4 drains the bounded accepted audio queue before finalizing recognition, explicitly ends audio and finishes the speech task, and keeps the phone audio session alive for up to ten seconds while awaiting a genuine final result. It preserves the existing on-device preference; it does not silently switch recognition to a server. Partial, empty, timed-out, interrupted or errored results do not trigger an agent request. Capture/recognition errors identify missing audio, missing words, timeout or a known Apple service name with its numeric code; they do not print transcript, audio or credential contents. An idle speech player no longer deactivates an active microphone when Watch state updates arrive.

Recordings are limited to 60 seconds on iPhone and 30 seconds on Watch. Reaching the limit asks for a shorter request rather than saving partial speech automatically. Replies are spoken by the active conversation device with matching captions and a Stop speaking control.

If live transcription stays empty, test on the actual unlocked iPhone after ending any active mirroring session, and check whether Voice Memos can record. Apple documents that microphone/camera access is unavailable during [iPhone Mirroring](https://support.apple.com/en-us/120421). That limitation applies when iPhone Mirroring is being used; it does not prove that every Mac connection or device-preview window causes the same restriction. The owner reported phone words/reply and Voice Memos working after stopping a Mac connection, but the exact connection type, installed build and root cause were not established.

The phone may receive Watch work during a finite background window, but the complete foreground/background/locked/force-quit path needs hardware testing. Keep the apps open during initial development checks. An unavailable phone or delayed reply must not be interpreted as proof that nothing was saved; inspect Notes before repeating a request whose result is uncertain.

## Inline note editing (TestFlight 7)

Tap a saved note's title or body to type directly on the note screen. There is no separate edit sheet or pencil action. Changes save after a 600 ms pause, when editing ends, when leaving the note and when the app becomes inactive. An empty title saves as “Untitled”. The keyboard's Done control ends typing; it is not a separate save requirement. New-note creation still has its own composer.

Opening “Update this note”, checking checklist items or using note Undo first flushes pending typing. Title/body edits preserve simultaneous changes to untouched fields and checklist items. If both typing and the agent changed the same field, automatic saving stops and retains the typed draft in memory instead of overwriting the saved version. The note shows Retry save and an explicit Use saved version action. Store failures retain the draft while the app process remains alive; drafts that have not been saved are not a durable backup.

Verification: 49 package tests pass, including seven inline-edit cases covering automatic saving, reopening/Undo, concurrent voice edits, conflict recovery, in-flight typing and validation. The native phone/Watch Simulator build passes. On the iPhone Simulator, directly edited title/body values were checked in the saved snapshot and after navigating away and reopening. This is included in the processed TestFlight build 7; physical acceptance remains pending.

## Next-release animation, Watch voice and Drive source

New companion creation uses two image requests: artwork, then a reference-based 20-frame sheet. Preparation and playback are local. If the sheet cannot be prepared, the saved base artwork stays usable and Animate this companion retries it. Preview animations cycles the states; Regenerate animations can replace an existing custom pack using its first frame as the identity reference. The same cached companion is delivered to Watch. Tap an idle companion on either device to dance. Pose changes have a 240 ms blend; breathing and sway are continuous local transforms. These effects are frame animation, not a 3D body rig or phoneme-driven lip synchronization. Every state has an assigned visual; errors use a calm neutral pose with the actual error message. Reduce Motion disables motion.

Settings → Voice → Watch reply voice offers Use iPhone voice, Automatic on Watch and reported installed Watch voices. Use iPhone voice renders a bounded short AAC reply on iPhone and sends it to Watch for playback. The voice pack stays on iPhone. Rendering/delivery/startup failures fall back once to local Watch speech; stopping playback preserves the text and saved notes. This path has wire/runtime tests and a Simulator AAC render/readback/cancellation check. Physical Premium voice parity still needs the owner's phone/Watch test.

Settings → Google Drive connects the user's own account for optional outbound Markdown copies. See [Drive setup and limits](google-drive.md). Google sign-in entry and cancellation were tested in Simulator without granting an account access; the owner chose to perform real authorization and upload after the TestFlight update. These additions are included in the processed TestFlight build 7. The owner later confirmed a real personal-account Markdown upload and it rendered correctly in Drive web preview. Repeated remote updates, TXT mobile preview, Muse access and physical Premium voice parity remain pending.

## Local data and recovery

The app saves an atomic JSON snapshot under its protected Application Support `Notes/notes.json` folder. The snapshot contains notes, revisions and edit/retry receipts, including before/after note values for safe Undo. Character PNGs and a manifest are cached separately under Application Support `Companion`. Keys are in Keychain. Recorded audio and conversational messages are not saved as an archive.

One `LocalTaskStore` actor owns the notes file. If saved data cannot be opened, the app preserves it and presents an error rather than silently replacing it with an empty notebook. Back up important notes before testing unfinished builds. Key removal, Start fresh and companion changes do not erase notes.

For current test scope and outstanding gates, see [release evidence](release-evidence.md).

## Choose the reasoning model

In iPhone Settings, tap **About → Reasoning** and choose **Muse Spark** (default) or **Muse Wonder**. The choice is saved locally and applies to both phone and paired Watch requests. Change it between replies; it does not clear temporary conversation or active note identity. Each complete tool loop keeps one model. Check connection tests the selected model against the catalog; unavailable access is reported without silently substituting another model. Artwork still uses Muse Image.

The live production Swift Wonder check passed seven checks with fictional groceries: ordinary reply without a note, checklist creation, duplicate-request recovery, scoped correction, checking off two items, persistence readback and Undo. This is Mac shared-agent evidence, not physical phone or Watch inference evidence.

## Talk startup

The primary control moves directly from Talk to Done during connection/microphone setup and stays Done while listening. Connecting or Preparing microphone describes setup; Listening begins after capture is ready. Pressing Done during setup ends the attempt without an agent request. Cancel is reserved for processing a submitted request. A late Watch Listening state cannot restart a recording stopped during setup.

## Drive format and voice preview (build 9)

Settings → Google Drive → File format offers Markdown (.md) or Plain text (.txt). The initial choice is Markdown. Selecting another format updates existing copies in place, including their names and media types. The same note/file IDs remain; no second file or imported cloud edit is created. Plain text is the mobile Drive compatibility option and keeps ordinary text/checklist marks. The owner’s real Markdown upload and web preview are confirmed; mobile TXT preview and Muse access still require device/account acceptance.

Preview iPhone voice sits immediately beneath Reply voice and above Watch reply voice. Choosing an installed Watch voice uses local synthesis, avoiding phone audio generation/transfer. The iPhone-voice option remains available; preferences are not migrated or overridden. Relative playback latency has not been measured on hardware.


## Rename a companion and read its original description (build 10)

Open Your companion, then tap a saved companion tile. This selects it and opens Companion details. Edit Name and tap Done; Cancel discards the name edit. The name is stored locally, retained after reopening and used in the companion's next agent turn. The default lion can also be renamed. Renaming needs no Meta request and leaves its artwork and original description unchanged.

Original description is selectable read-only text. If an older saved image has no retained description, Avatodo says it was not saved. Create a new companion is a separate form and does not edit existing generation descriptions. The bundled default lion has a clearer listening pose in this version; existing custom poses are kept unless you choose Regenerate animations.


## Pauses within one recording (build 10)

Speaking, pausing and continuing before Done remains one recording. The phone retains earlier timed recognition phrases while the current phrase changes. Corrections replace the matching audio interval, and a later full/cumulative result can revise earlier text without duplication. Watch uses the same phone recognition path and receives the complete live transcript. Done still waits for successful finalization before sending text to the agent. Cancellation or a new capture clears this RAM-only transcription; no audio or conversation archive is added. The existing 60-second phone and 30-second Watch capture bounds still apply.


## Clean Google Drive names (build 10)

Drive copies use the note title without an internal ID or added extension. File format selects plain text or Markdown in the file metadata; both formats keep the same Drive file ID. Duplicate or occupied titles get a simple number. Drive already shows modified date/time below the title, so uploads do not add timestamps to names. Upload now also renames existing copies of current notes on the same IDs. Copies of deleted local notes remain in Drive for the user to manage.
