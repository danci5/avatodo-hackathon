# Release evidence

Checkpoint: 4 November 2026. The speech-repair candidate is **0.1.0 (4)** from native source [`63043965c4753a44b89b6d46e9876ed998f48d53`](https://github.com/danci5/avatodo-hackathon/commit/63043965c4753a44b89b6d46e9876ed998f48d53). Its clean signed archive, App Store distribution export and upload succeeded. App Store Connect confirmed it fully processed as **Ready to Submit**, with a 90-day window and association with the internal group’s one invited owner. Build 4 installation remains unconfirmed. The owner reports phone catalog authentication and a typed reply now work after replacing the stored key, but Listening remains empty and Talk/Done fails. The owner says voice worked previously. The precise speech failure, complete voice-to-saved-result path and Watch installation are not established.

The repository is temporarily private during preparation at the owner's request; restore public visibility and repeat logged-out access checks before submission. Earlier native source `75c6c3f341284d0cea1cdc7ab68fba7f5aeb7d78` and the first checkpoint `705750446f00588b42b22beb139fa3443ce64c1d` remain the provenance for historical typed simulator/custom-artwork evidence below.

| Area | Current evidence |
|---|---|
| Repository | Temporarily private [danci5/avatodo-hackathon](https://github.com/danci5/avatodo-hackathon), Apache-2.0. Before visibility was changed on 4 November, unauthenticated access and a fresh mirror of all published branches were verified; a fresh public clone of native source `75c6c3f` built both Simulator targets successfully. Those are historical checks. Source, assets and generated project are included without another private dependency. Public visibility is a submission gate |
| Shared Swift domain/agent | 26 exact-source tests pass on macOS with Xcode 27 / Swift 6.4: the original 15 domain/agent cases, five HTTP/catalog cases and six speech-finalization cases. Speech cases reject partial/no-audio/empty/error/late-error results and additional audio after an earlier final; diagnostics cannot echo arbitrary error-domain text |
| Shared Swift live Meta | Seven production Swift agent/store checks passed with fictional data and passed again after the HTTP diagnostic changes. The production Swift catalog check also authenticated and listed both required models without inference. The earlier seven-request run took 16.13 seconds; see [live evidence](shared-swift-live-evidence.md). These Mac results do not validate the key stored on the phone |
| Earlier model access | Six direct Mac API checks passed for ordinary replies, fictional checklist actions, Muse Image generation and reference editing. The fixture writer was separate from the later production Swift agent check. See [access evidence](meta-access-evidence.md) |
| Native build | Candidate source `6304396` produced a clean Release archive with matching phone and embedded Watch at 0.1.0 (4). App Store export signatures/profiles verified for both bundles: paid team, get-task-allow false, beta reporting enabled and no ProvisionedDevices. This establishes packaging, not a physical speech pass |
| Native model UI | An ordinary typed phone reply created no note. The phone created/opened “Win the Meta Hackathon.” A typed request in the actual Watch UI reached the phone Meta agent/store and returned a Watch result; durable phone JSON contained exactly milk, eggs and bread plus the hackathon note |
| Exact-note edits and Undo | Real typed Update this note calls replaced milk with oat milk, then checked off eggs and bread. The note detail showed the saved changes. Its Undo restored the completion values while retaining oat milk. Closing/reopening the compact panel twice remained usable |
| Keychain | A normally signed phone simulator saved the key and retained it through reinstall/relaunch. Unsigned installation failed key storage. Mac credentials do not automatically synchronize to physical devices |
| Custom companion | The phone UI made a real `muse-image-1.0` request, prepared a PNG locally and displayed it. Both simulator caches contain the same selected manifest and valid PNG hash; actual phone/Watch displays were inspected. The bundled default and app icon remain separate assets |
| Character transport | Six current-source checks pass for reordered/duplicate chunks, delayed selection, reset/stale delivery, newer selection, corrupted hash and conflicting/oversized metadata. Foreground chunks supplement background file transfer. Physical/reconnect/background reliability remains unaccepted |
| Speech | Six bounded audio-queue checks pass, including concurrent conversion/close draining, overflow/conversion failure and cancellation isolation. Four synthetic 16/24/44.1/48 kHz conversion cases pass. Build 4 retains the recognizer, explicitly finishes buffer recognition, drains accepted audio before finalization and preserves microphone session ownership. The earlier Simulator CoreAudio failure remains; microphone capture is disabled there by default with typed fallback |
| Physical voice | The owner reports phone catalog authentication and typed inference now work. Talk/Done still fails with an empty Listening transcript; the owner reports voice previously worked. No precise physical failure cause is confirmed. Build 4 repairs source lifecycle hazards but has not passed hardware speech. Voice-to-response/save, Watch audio/speaker, unavailable/locked/background and interrupted execution remain unaccepted; Watch installation is unconfirmed |
| Consent and privacy | Consent defaults to denied and gates typed, phone voice, Watch and companion creation requests. Simulator UI checks on source `24a0ffc` passed denial, explicit grant, relaunch persistence, revocation and the live privacy link. Build 2 adds the 18+ notice and consent v2; the local permission check confirms an old v1 grant cannot bypass it. Exported builds 2, 3 and 4 contain the v2 key/notice and explicit Other User Content → App Functionality, linked true, tracking false, alongside UserDefaults CA92.1. No model request was sent by these permission checks |
| Accessibility/appearance | Native layouts and custom artwork were inspected in simulators. Reduce Motion and long-text behavior exist in source. Full light/dark, VoiceOver, Dynamic Type and physical touch/scroll acceptance remains in progress |
| TestFlight | Builds 1, 2, 3 and 4 uploaded successfully and remain recorded. App Store Connect showed 0.1.0 (4) fully processed, Ready to Submit, with a 90-day testing window and association with the internal group’s one Invited owner tester. The owner previously reported an installed phone build and typed inference; build 4 and Watch installation are not yet confirmed. The external group has zero testers and zero builds; no Beta Review submission or public link is active |
| App Store release | No App Store review approval or public release |
| Demo / submission | Three-minute video not produced; hackathon entry not submitted |

## Build and distribution record

| Stage | Verified result |
|---|---|
| Source | Native source `63043965c4753a44b89b6d46e9876ed998f48d53` pushed to the private origin and remote SHA matched; archive was made from a clean working tree |
| Archive | Clean 0.1.0 (4) archive passed with matching phone/Watch identifiers and versions; both use the verified paid team |
| Distribution export | App Store export succeeded; both signatures/profiles verified, debugger entitlement false, no device-limited provisioning |
| Local exported IPA | 6,501,693 bytes; SHA-256 `2354bcd42c049895326fff72113413a654749e26777a9fb6aa0fdb353fd4f43b` |
| Upload | Standard Xcode upload of build 4 succeeded on 4 November at 17:40:21 UTC (18:40:21 CET), exit 0; Apple reported processing. Xcode repackaged the same archive, so the IPA hash above identifies the separately verified local export, not an independently observed uploaded byte stream |
| Processing / invitation | App Store Connect UI confirmed fully processed build 4, Ready to Submit, internal-group association and one Invited owner tester. The phone catalog and typed-inference passes are user reports on an earlier install; neither build 4 installation nor full physical voice/Watch acceptance is confirmed |

Build 1 from `24a0ffc99705ede6426fc43aa8ae29d40f46bb36` uploaded successfully at 15:48:12 UTC. Build 2 from `8cccda7c9dbc837abd5711dcdb737a01ec5e4db4` uploaded at 16:11:21 UTC; it corrected remote-content collection metadata and the age/permission notice. Its verified local export was 6,406,871 bytes, SHA-256 `c9e09178b280bfe71953333f1fd036b81cb1aa85e4e0f90b0992310bcb3e77b0`. Build 3 from `8c10f993c43b35706f3dca9d9ad501eb4e980fd7` uploaded at 17:02:15 UTC, then fully processed and joined the internal group. Its verified local export was 6,431,309 bytes, SHA-256 `3bf7a38e4a19798e50dd872b0dbc35608d3b67bfaa40ecb6831b4d414b852445`. Earlier uploads remain in the record; build 4 preserves their privacy and authentication corrections.

## Build 3 authentication diagnostic

Build 3 adds an explicit **Settings → Check connection** control. It uses the same production Meta client to fetch the model catalog, sends no notes or inference, and reports authentication separately from model availability. HTTP 401 now says the key was rejected; HTTP 403 says Meta denied the request. Provider error bodies and credentials are never displayed by the diagnostic. Saving a key establishes storage only.

The owner’s installed TestFlight build 2 reached a generic authentication/access error after Talk/Done. A non-erasing development build 3 update then installed on the phone. Its Check connection returned HTTP 401. After the owner used **Copy Password to Clipboard** in Mac Keychain and pasted into the secure field on the actual iPhone, the owner confirmed the key was accepted and both required models were listed. This is a user-reported physical phone catalog-authentication pass; no key was displayed to the agent, included in the build or shared with Apple. The owner subsequently reported that a typed request produced a reply. This is user-reported phone inference, not a voice or saved-action pass; physical voice/actions remain pending.

Watch installation stalled during this period. The temporary development phone update embedded a Watch development profile without the paired Watch’s identifier, which may have interfered; no definitive installer cause is established. Build 3’s exported App Store phone and Watch profiles have no device restrictions. The owner was instructed to cancel the stalled attempt, update the phone through TestFlight 3 and retry Show App on Apple Watch. Installation has not yet been confirmed.

The build 3 Release device build and clean archive passed with matching phone/Watch versions. Its 20 core tests, real production Swift catalog check and seven real production agent/store checks passed on Mac. Those Mac checks are separate from the reported phone catalog result and do not establish phone inference, voice or saved-result acceptance. Build 3 distribution/upload/processing are recorded above.

## Build 4 speech lifecycle repair

The owner reports that Listening remains empty and Talk/Done fails despite typed inference working, and that voice worked previously. The original speech implementation had not changed during the authentication repair; a transient Apple service or route issue remains possible. No exact physical cause is claimed.

The source repair retains the recognizer, drains bounded PCM before finalization, calls both endAudio and task.finish, keeps the phone audio session active while waiting up to ten seconds for a final result, and cancels without sending partial speech. The queue serializes conversion with closure and fails closed on overflow or conversion error. Idle playback cleanup no longer deactivates the microphone during nonspeaking Watch state refreshes. Watch capture detaches canceled task handles and fences late Listening states after Done. Cancellation clears speech text from RAM.

New errors distinguish unavailable recognition, microphone/capture failure, no submitted audio, no recognized words, finalization timeout and an allowlisted Apple error domain plus numeric code. No raw service error body, transcript, audio or key is logged. A callback error rejects a result even when the callback also marks it final. On-device preference remains unchanged. These are tested source corrections and clean distribution evidence; build 4 physical acceptance remains pending.

## External review access gate

No external Beta Review has been submitted and no public testing link is enabled. Before that step, align App Store Connect privacy answers with actual third-party processing and establish a legitimate way for reviewers to exercise the Meta features. Do not declare Data Not Collected merely because there is no Avatodo server: relevant text and notes go to Meta, whose retention is separate from local conversation expiry.

[Meta Model API Terms §3.1](https://dev.meta.ai/legal/terms-of-service) require prior written permission before sharing an API key with a third party. Do not provide the existing development key to Apple, put it in review notes, or embed it in a build. Provider-approved review access remains unresolved; no key-sharing permission is assumed. Meta features also require users aged 18 or older under §10.1.

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

[Phone custom companion](images/phone-custom-companion.png) and [Watch custom companion](images/watch-custom-companion.png) are historical native Ready-screen captures from the installed `75c6c3f` simulator source. The [capture manifest](images/capture-manifest.json) records their hashes, device/runtime and source commit. These captures do not show a saved action or prove microphone use. [Earlier phone saved-note capture](images/phone-live-note.png) and [bundled Watch Ready capture](images/watch-native-ready.png) predate the final native source checkpoint; neither is physical-device evidence.

## Voice limitation and remaining gates

Experimental Simulator capture requires `AVATODO_ENABLE_SIMULATOR_MICROPHONE=1`. That path has not passed live voice on this host; physical capture is unchanged. Only finalized speech may trigger tools, and incomplete/interrupted audio must not execute a partial request. A missing reply does not prove nothing was saved.

Before a device release, record exact signed source/build, device/OS and measured latency; verify full command-to-saved-result recordings, persistence after reopening, lost/duplicate delivery, invalid key, no network, permission denial, background expiration, locked/force-quit phone, interrupted playback and failed character transfer. The historical `75c6c3f` source built from a fresh public clone before the repository became private; that is not a fresh public-clone check of the later TestFlight candidate. Repeat public access/build checks for the submission source. None of the build, typed Simulator or model-access evidence substitutes for those hardware checks.

Inspect the final three-minute film and public repository from a logged-out browser before submission. Show only completed event work, label Simulator footage and any sped-up waits, and do not present an unimplemented flow as working.

Apple’s [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) distinguishes upload, invitation, installation and review, and documents the 90-day testing window. Apple’s [Developer Mode guidance](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) separates Xcode development from TestFlight installation.
