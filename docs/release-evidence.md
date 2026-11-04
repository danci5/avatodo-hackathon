# Release evidence

Checkpoint: 4 November 2026. Native source is published at [`75c6c3f341284d0cea1cdc7ab68fba7f5aeb7d78`](https://github.com/danci5/avatodo-hackathon/commit/75c6c3f341284d0cea1cdc7ab68fba7f5aeb7d78), following the first native checkpoint `705750446f00588b42b22beb139fa3443ce64c1d`. This is developer source, not an installable App Store/TestFlight release. Observed simulator results and pending physical acceptance are distinguished below.

| Area | Current evidence |
|---|---|
| Repository | Public [danci5/avatodo-hackathon](https://github.com/danci5/avatodo-hackathon), Apache-2.0. Unauthenticated access and a fresh mirror of all published branches were verified on 4 November. A fresh unauthenticated public clone of native source `75c6c3f` built both Simulator targets successfully. Source, assets and generated project are included without a private dependency |
| Shared Swift domain/agent | 15 current-source tests pass on macOS with Xcode 27 / Swift 6.4: atomic persistence/Undo, strict scope, non-mutating chat, twenty additions despite history trimming, retry/restart recovery, protected idle expiry and truthful failed writes |
| Shared Swift live Meta | Seven production Swift agent/store checks passed: seven Meta requests, 16.13 seconds, fictional data. See [live evidence](shared-swift-live-evidence.md) |
| Earlier model access | Six direct Mac API checks passed for ordinary replies, fictional checklist actions, Muse Image generation and reference editing. The fixture writer was separate from the later production Swift agent check. See [access evidence](meta-access-evidence.md) |
| Native build | Both normally signed simulator targets build from the published native source. Generic device SDK compilation also passed at the first native checkpoint with signing disabled; that was not a signed device install |
| Native model UI | An ordinary typed phone reply created no note. The phone created/opened “Win the Meta Hackathon.” A typed request in the actual Watch UI reached the phone Meta agent/store and returned a Watch result; durable phone JSON contained exactly milk, eggs and bread plus the hackathon note |
| Exact-note edits and Undo | Real typed Update this note calls replaced milk with oat milk, then checked off eggs and bread. The note detail showed the saved changes. Its Undo restored the completion values while retaining oat milk. Closing/reopening the compact panel twice remained usable |
| Keychain | A normally signed phone simulator saved the key and retained it through reinstall/relaunch. Unsigned installation failed key storage. Mac credentials do not automatically synchronize to physical devices |
| Custom companion | The phone UI made a real `muse-image-1.0` request, prepared a PNG locally and displayed it. Both simulator caches contain the same selected manifest and valid PNG hash; actual phone/Watch displays were inspected. The bundled default and app icon remain separate assets |
| Character transport | Six current-source checks pass for reordered/duplicate chunks, delayed selection, reset/stale delivery, newer selection, corrupted hash and conflicting/oversized metadata. Foreground chunks supplement background file transfer. Physical/reconnect/background reliability remains unaccepted |
| Speech | Four synthetic 16/24/44.1/48 kHz conversion cases pass. The speech-permission callback repair reached Listening. The tested iOS 26 Simulator then aborted in CoreAudio microphone capture, including after an input-route retry. Simulator capture is now disabled by default with a tested typed fallback |
| Physical voice | Microphone, recognition, Watch audio, origin-device speaker, unavailable/locked/background and interrupted execution have not passed on paired hardware. Both physical devices were unavailable at the last discovery check |
| Accessibility/appearance | Native layouts and custom artwork were inspected in simulators. Reduce Motion and long-text behavior exist in source. Full light/dark, VoiceOver, Dynamic Type and physical touch/scroll acceptance remains in progress |
| Installable release | No App Store or TestFlight release |
| Demo / submission | Three-minute video not produced; hackathon entry not submitted |

## What the tests establish

The local tests use fictional data and verify mutations, failed transactions, revisions/Undo, exact-note scope, repeated operations, durable receipts and temporary session rules. They do not prove semantic model reliability, speech or physical transport.

The live production Swift check verifies actual Meta tool selection: ordinary chat creates no note, a grocery checklist is saved, request replay does not duplicate it, milk becomes oat milk, eggs/bread are completed, reopened state matches, and local Undo restores completion values. This was separate from the subsequent native UI interactions.

The first persistence adapter is atomic JSON owned by one actor. There is no SwiftData integration claim. Conversation is RAM-only; notes and operational retry/Undo receipts are durable.

## Native custom companion record

The in-app prompt described a little lion with black Wayfarer sunglasses, soft golden fur and a friendly confident smile. Muse Image returned artwork, which the phone prepared and cached locally. Its name is Ava; selecting it did not change the blue-lion app icon.

- Selected manifest: `448F5C6E-9899-460A-9120-3AF4E38D2837`
- Prepared PNG: 205,508 bytes
- SHA-256: `775564fe68e4dccd76a01404243d8c4cf9d227154987044be1ef99d04c21add9`
- Phone and Watch manifests and PNG hashes matched after foreground transfer.
- Motion is local SwiftUI breathing/tilt/state motion from one image, not generated video, expression frames or lip synchronization.

[Phone custom companion](images/phone-custom-companion.png) and [Watch custom companion](images/watch-custom-companion.png) are native Ready-screen captures from the installed published native source. The [capture manifest](images/capture-manifest.json) records their hashes, device/runtime and source commit. These captures do not show a saved action or prove microphone use. [Earlier phone saved-note capture](images/phone-live-note.png) and [bundled Watch Ready capture](images/watch-native-ready.png) predate the final native source checkpoint; neither is physical-device evidence.

## Voice limitation and remaining gates

Experimental Simulator capture requires `AVATODO_ENABLE_SIMULATOR_MICROPHONE=1`. That path has not passed live voice on this host; physical capture is unchanged. Only finalized speech may trigger tools, and incomplete/interrupted audio must not execute a partial request. A missing reply does not prove nothing was saved.

Before a device release, record exact signed source/build, device/OS and measured latency; verify full command-to-saved-result recordings, persistence after reopening, lost/duplicate delivery, invalid key, no network, permission denial, background expiration, locked/force-quit phone, interrupted playback and failed character transfer. The current native source has built from a fresh public clone; repeat that check if release source changes. None of the build, typed Simulator or model-access evidence substitutes for those hardware checks.

Inspect the final three-minute film and public repository from a logged-out browser before submission. Show only completed event work, label Simulator footage and any sped-up waits, and do not present an unimplemented flow as working.
