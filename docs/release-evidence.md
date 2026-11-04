# Release evidence

Checkpoint: 4 November 2026. This records observed results separately from source-level behavior and pending device acceptance. The current native integration is not yet a published, installable release; a final source commit and capture manifest must be recorded before release claims.

| Area | Current evidence |
|---|---|
| Repository | Public [danci5/avatodo-hackathon](https://github.com/danci5/avatodo-hackathon), Apache-2.0. Unauthenticated access and a fresh mirror of every published branch were verified on 4 November. Current native changes still need their final published-source checkpoint |
| Shared Swift domain/agent | 15 current-source tests passed on macOS with Xcode 27 / Swift 6.4. Includes atomic persistence/Undo, scope, ordinary non-mutating chat, history trimming without limiting twenty additions, retry/restart recovery, protected idle expiry and truthful failed writes |
| Shared Swift live Meta | Seven checks passed using actual `CompanionAgent`, `MetaClient` and atomic `LocalTaskStore`: seven Meta requests, 16.13 seconds total, fictional data. See [live evidence](shared-swift-live-evidence.md) |
| Earlier model access | Six direct Mac API checks passed for ordinary replies, fictional checklist tool/follow-ups, Muse Image generation and reference editing. See [access evidence](meta-access-evidence.md); that fixture writer was separate from the later real Swift agent check |
| Native simulator build | Both normally signed simulator targets built after the speech-authorization repair and again after the simulator-only microphone fallback gate. Later source edits still need rebuilding; final source commit/publication remains pending |
| Native model UI | iPhone simulator produced an ordinary typed reply without a note, then created and opened “Win the Meta Hackathon.” A typed request in the actual Watch simulator UI crossed Watch Connectivity to the iPhone Meta agent/store and returned a displayed Watch result; durable phone JSON contained exactly milk, eggs and bread alongside the original hackathon note. This proves a paired-simulator typed path, not voice or physical-device behavior |
| Keychain | The normally signed iPhone simulator saved the key and retained it through reinstall/relaunch. Unsigned installation failed key storage. Mac development credentials do not automatically synchronize to a physical phone or Watch |
| Character | Approved default 3D lion and blue-lion icon are bundled with provenance. Native custom-generation, local Vision/edge preparation, manifest/transfer and procedural-motion source exist. Full custom creation/transfer on the real app and final icon/device acceptance remain pending |
| UI | Production native screens were inspected in simulators, including default companion, real phone note creation/opening and real typed Watch request/result. Exact-note typed milk-to-oat-milk correction and two close/reopen attempts of Update this note passed. Full light/dark/accessibility and physical touch/scroll checks remain in progress |
| Speech and paired transport | Typed Watch command/result and synthetic 16/24/44.1/48 kHz conversion checks passed. The Swift 6 speech-permission callback repair reached Listening in the real UI. The tested iOS 26 simulator then aborted in its CoreAudio microphone service, including after an explicit input-route retry. A simulator-only default microphone gate now gives a tested graceful typed fallback; live voice, Watch audio and interrupted/background/locked execution have not passed |
| Physical SDK compile | Generic iOS-device SDK plus embedded Watch SDK compiled successfully with signing disabled. This is a compile-only check, not a signed device install, runtime or physical acceptance |
| Physical iPhone/Watch | Exact available devices/OS, signing and full real command-to-saved-result flow are not accepted. Reported OS versions are not device-test evidence |
| Installable app / TestFlight | Not released |
| Demo video / hackathon submission | Not produced / not submitted |

## What the checks establish

The local tests use fictional data. They verify task mutations, transaction failures, revision/Undo safeguards, ambiguous exact titles, strict selected-note scope, repeated operations, durable receipts and the temporary agent-session contract. They do not prove semantic model reliability, speech, transport or physical-device behavior.

The live shared Swift check verifies actual Meta tool selection through the production Swift store: ordinary chat creates no note; one grocery checklist is created; request replay does not duplicate it; milk changes to oat milk; eggs and bread are checked off; reopening matches saved state; local Undo restores the prior completion values. It does not test native UI, microphone, Watch or custom artwork creation.

The first native persistence adapter is atomic JSON owned by one actor. There is no SwiftData integration claim. The default artwork/icon and local native motion are separate from a successful in-app Muse Image pipeline.

## Remaining release record

Before release, preserve the exact source commit, build/test results, model IDs, device/OS and signing configuration, measured latency, full command-to-saved-result recordings, artwork provenance and limitations. Verify note persistence after reopening, duplicate/lost delivery, pending results, invalid key, speech permissions, no network, background expiration, interrupted playback, failed character transfer and accessibility on the supported physical setup. Confirm that a fresh public clone builds without private files.

Inspect the final three-minute video and public repository from a logged-out browser before submission. A compiled app, public source, captured simulator or model-access check does not by itself establish a physical-device release or submitted entry.


## Current-source paired-simulator checkpoint

The app-repository source built both normally signed simulator targets after the Swift 6 speech-authorization callback repair. The fifteen core checks and four synthetic audio-rate cases passed. The synthetic cases verify duration/bandwidth, amplitude and frequency after conversion; they do not prove microphone capture or live recognition.

The actual iPhone UI returned a normal typed Meta reply without making a note, then created and opened **Win the Meta Hackathon**. Its Keychain key survived reinstall/relaunch. In the actual Watch UI, a typed request to make a grocery list with milk, eggs and bread was delivered over Watch Connectivity to the iPhone agent, interpreted through Meta, committed to local storage and returned as a Watch result. Readback of the phone's durable JSON found those exact three grocery items and the existing hackathon note.

[Phone simulator after the real saved-note request](images/phone-live-note.png). [Watch native Ready screen](images/watch-native-ready.png) shows only the bundled companion and Talk control; it is not a saved-result capture. The typed Watch result was observed during interaction and checked against durable phone JSON, but no final Watch result image is recorded here. Neither image proves physical speech or a completed three-minute demo. Final source revision/publication remains to be recorded.

The speech-authorization callback repair was retested and the UI reached Listening. The next failure was the simulator CoreAudio microphone-service abort, which persisted after choosing the MacBook microphone explicitly. The default simulator-only capture gate and graceful typed fallback were then exercised without that crash. Experimental simulator capture requires `AVATODO_ENABLE_SIMULATOR_MICROPHONE=1`; the physical capture implementation is unchanged. Complete recording/recognition/playback and unavailable/locked/background/interrupted behavior still require actual paired-hardware verification.


Post-audio-gate build checkpoint: both normally signed simulator targets compiled successfully. A generic physical iOS-device build with embedded Watch SDK also passed with signing disabled; it was not installed or run on physical devices. A connected/unlocked iPhone is still needed for the hardware trial. Pending note-panel source adjustments must be rebuilt before final source evidence is sealed.

Native note-scope follow-up: the actual Update this note action successfully changed milk to oat milk through a typed model request, and closing/reopening that compact panel twice remained usable. The subsequent eggs/bread completion request is not included as a passed result at this checkpoint.
