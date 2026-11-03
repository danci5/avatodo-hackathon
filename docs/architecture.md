# First-release architecture

Status: implementation contract; device behavior remains to be tested.

## Responsibilities

| Layer | Owns |
|---|---|
| iPhone app | Companion setup, voice/text input, local agent loop, notes/checklists, provider credentials and animation preparation |
| Watch app | Companion presentation, bounded push-to-talk, captions, spoken replies and a small cached view of current results |
| Local task domain | Typed create/read/update/delete/complete/undo actions, stable IDs, revision checks and retry receipts |
| Meta language adapter | Remote interpretation and tool selection; no authority to claim a write succeeded |
| Muse Image adapter | Direct remote generation and reference-based image edits |
| Companion runtime | Cached expressions and local motion for idle/listening/thinking/speaking/success |
| Paired-device transport | Bounded commands, audio where needed, truthful status, note snapshots and versioned character packages |

The iPhone is the source of truth. The intended app persistence adapter is SwiftData. A pure Swift domain package should keep model/provider code and UI out of domain operations. Transfer only needed state to the paired Watch; never the provider key.

## Speech and connectivity

Start with tap-to-talk, an explicit stop control and visible transcription. Evaluate Apple speech recognition on the actual phone/locale and system speech synthesis on the active device. On-device speech availability must be tested rather than assumed. Watch audio may be relayed to iPhone for transcription.

The first hardware trial must establish what works with the paired phone foregrounded, backgrounded, locked or unreachable. Do not promise autonomous Watch operation until measured. A queued request is pending, not saved. Offline notes remain readable; remote reasoning/image requests need connectivity.

## Model action loop

1. Capture text and relevant active-note context.
2. Send a bounded request to the configured Meta language model.
3. Validate returned tool names, arguments, IDs and expected revision.
4. Apply local operations transactionally, using a mutation identifier for retry safety.
5. Return actual outcomes to the agent and render/speak a truthful reply.
6. Update the foreground Watch from committed state.

Ambiguous targets require clarification. Deletions need a user-visible confirmation or a recoverable undo path. No external execution, purchase or message sending is part of this example agent.

## Character creation

Voice/text description → direct Muse Image request → canonical artwork and a few consistent expression images → local crop/alignment/validation → versioned cached package → Watch transfer.

Simple breathing, tilting, bouncing and expression changes create motion. Muse Image returns images, not a complete Watch animation engine. Keep an opaque background fallback if masking fails. Preserve the last valid character on errors. The reference demo character is a little lion wearing Ray-Ban glasses; generated output must be validated before the demo.

## Public boundaries

No Avatodo-hosted backend, mandatory sign-in, remote MCP service or shared developer API key. Provider/model IDs are configured only after account access is verified. Keep documentation clear about API usage costs and provider data handling.
