# First-release architecture

The agent executes inside the iPhone app. Meta supplies remote language reasoning and image generation through direct HTTPS calls; Avatodo runs no application server.

## Responsibilities

| Layer | Owns |
|---|---|
| iPhone app | Companion setup, voice/text input, local agent loop, notes, Keychain credentials and image preparation |
| Watch app | Same companion, push-to-talk, transient captions, local speech playback and cached character artwork |
| Local task store | Typed mutations, stable note/item IDs, revision checks, atomic snapshots and retry/Undo receipts |
| CompanionAgent | Bounded tool loop, temporary multi-turn context, note selection, strict note scope and truthful outcomes |
| MetaClient | Direct `muse-spark-1.3` language/tool requests and `muse-image-1.0` artwork requests |
| Apple speech adapters | iPhone recognition and active-device speech synthesis |
| Watch Connectivity | Bounded commands/audio, ordered transient state and validated character files; no API key |
| SwiftUI companion runtime | Cached artwork with local phase-driven motion and reduced-motion support |

## Durable notes and temporary conversation

One `LocalTaskStore` actor owns the iPhone's atomic JSON snapshot of notes, revisions and operational mutation receipts. This is the native app's first persistence adapter; there is no separate SwiftData store. A candidate mutation is validated and written before the in-memory store publishes success. Replaying a mutation ID returns its original receipt; conflicting reuse and stale revisions fail. Receipts include before/after note values for Undo and interrupted-request recovery, not conversational transcripts. One store owns each file; multiple processes must not write the same snapshot.

Conversation exists only in RAM. The agent retains at most six complete exchanges, keeping tool requests with their results. Active note identity is separate, so evicting old words does not impose a six-item or six-turn limit. Notes are the lasting semantic context. There is no saved chat, compaction summary or inferred profile memory.

The session expires after five idle minutes, measured after reply presentation or speech completion/stop. Recording, tool execution and reply presentation protect active work from expiry. Start fresh clears temporary words and note references while preserving notes and valid note-side Undo. The Watch receives transient deadlines so reconnecting does not revive expired captions or Undo.

General requests can search titles, bodies and checklist labels, then read the current note and revision. Ambiguous targets should be clarified. **Update this note** supplies the exact note ID and enforces that scope; the agent cannot silently write another note or create a different one from that panel.

## Model action loop

1. Finalize input and obtain relevant current note context.
2. Call Meta directly using the key read from iPhone Keychain.
3. Validate tool names, arguments, real IDs, scope and expected revisions.
4. Commit typed operations through the local store using retry-safe identities.
5. Send actual tool outcomes back to the model and show/speak the result.
6. Refresh notes and the paired Watch from committed state.

Ordinary replies return without a write or saved-note card. A failed tool write cannot be presented as saved. Cancel stops outstanding capture or work; it does not reverse an operation that already committed. **Stop speaking stops playback only.** Undo is a separate validated mutation, available only while the affected revision still permits reversal.

## Speech and paired-device behavior

Both devices use explicit tap-to-talk and Done. iPhone recognition reports partial text; only a finalized utterance is submitted to the agent. Watch audio is relayed as bounded, sequenced mono 16 kHz Int16 PCM to the iPhone recognizer, and partial captions return to Watch. Missing/out-of-order audio is buffered within limits; incomplete capture must not execute a partial request. Audio buffers and captions are not written to disk.

Capture is bounded to 60 seconds on iPhone and 30 seconds on Watch. A recording limit ends capture with a retry message rather than automatically committing the utterance. Apple recognition runs on device where the current recognizer supports it; locale/device availability and any Apple speech-service fallback need testing. Speech playback uses system voices on the conversation's originating device, without duplicate iPhone playback for a Watch-originated reply.

Watch Connectivity and a finite iPhone background execution window support the relay. They do not make the phone an always-running service or the Watch a standalone agent. Foreground, background, locked, first-unlock-after-restart, force-quit, unreachable-phone and interruption cases require physical-device verification without a debugger. Those cases are not yet accepted.

A timeout or missing reply does not prove the notes are unchanged. Request identities and committed receipts support reconciliation; the UI should direct the person to check saved state when completion is uncertain. Keys use device-only after-first-unlock Keychain accessibility. Notes use an app-owned protected Application Support folder. Neither setting alone proves locked-phone operation.

## Companion creation and motion

The included 3D lion and blue-lion brand icon are bundled, so viewing the default companion needs no image request. People can keep that companion or create a custom one without changing the app's brand icon.

Custom creation follows this source path:

Description → direct Muse Image request → local foreground separation/crop/resize → validated PNG and manifest → cached native display → Watch transfer.

Local preparation uses Apple Vision where available, with deterministic edge-connected white removal as a fallback. The manifest includes character identity, hash and provenance. Background file transfer is supplemented by acknowledged 24 KB foreground chunks while reachable. Assembly is bounded to one image of at most 4 MB; Watch validates the final hash and current selected character before installation. Default resets and newer selections reject stale transfers. The same prepared image is animated locally through gentle breathing, tilt and phase-driven motion, respecting Reduce Motion.

The current baseline uses one canonical image and procedural motion. Generated expression frames, lip synchronization and generated video are not implemented claims. A real in-app Muse Image request, local preparation and matching custom PNG caches/display on both paired simulators have passed. This does not establish physical-device or background-transfer reliability.

## Public boundaries

The public repository includes native targets, shared Swift code, artwork/provenance and setup files. It has no private build dependency, hosted agent/MCP endpoint, database service, mandatory login or shared developer key. Relevant note data and prompts leave the device for Meta inference; local non-retention does not promise zero retention by Meta or Apple. See [release evidence](release-evidence.md) for what has actually been tested.
