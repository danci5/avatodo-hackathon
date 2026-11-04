# Local task engine and agent

`AvatodoCore` separates the validated local task domain from the remote model adapter and temporary conversation loop. The task store itself needs no model, UI, network or account; the same package also contains `MetaClient`, typed model tools and `CompanionAgent` for the app. The package alone is not an installable phone/Watch app.

Run the focused macOS checks with a compatible Swift 6 toolchain:

```sh
bash scripts/test.sh
```

The script keeps build and compiler caches in ignored `.build`. These tests need no API key. The separate opt-in [live Swift probe](shared-swift-live-evidence.md) sends billable requests with fictional data.

## Supported operations

- Create, read, edit and delete notes, tasks and checklists.
- Append note text, complete a task, add/rename/remove checklist items, and complete or reopen several items together.
- Undo a successful mutation if that record has not subsequently changed.
- Resolve exact case-insensitive titles, rejecting ambiguous matches; model tools also provide bounded search over titles, bodies and checklist labels, plus read-by-ID.

Every mutation carries a request ID. Replaying the same request returns its existing receipt; conflicting payload reuse fails. The receipt represents a historical mutation, so fetch current state for display and avoid repeating success effects for an already handled ID.

Edits carry the revision read by the agent. Stale edits fail instead of overwriting newer work. Checklist changes use item IDs, preserving identity when milk becomes oat milk. Multi-item requests are validated before any change. Deleted IDs and revisions remain reserved, including after Undo.

## Durable writes

`LocalTaskStore` serializes mutations in one actor. It computes a candidate snapshot, saves it, then publishes new state and the committed receipt. A failed save leaves in-memory state untouched. Notes, revisions and retry receipts are one transaction.

`JSONFilePersistence` uses atomic file replacement and is also the first native iPhone persistence adapter. It supports reopening and operational receipt recovery across process lifetimes. One store owns a file; cross-process/multiple-store writers are unsupported. Receipts retain before/after note values for Undo and safe retry recovery. They are not saved chat transcripts. Do not place user notes or snapshots in the repository.

## Agent boundary

`CompanionAgent` calls `MetaClient` with the current note context and tool catalog. `NoteTools` validates arguments, IDs, strict selected-note scope and revisions before executing `TaskAction`. Only committed outcomes can support a saved confirmation; unresolved failed writes override a misleading model success reply.

The temporary session keeps at most six complete exchanges in RAM, independently retaining active note identity. Twenty follow-up additions can still target the same note after older exchanges are evicted. Five idle minutes or Start fresh discard conversation context while leaving notes and valid Undo receipts intact. Recording/reply presentation and execution must not be expired in the middle of an active turn.

Ordinary chat returns without a mutation. A compact note-specific interaction enforces the exact selected note ID. General interactions can search/read notes and should clarify ambiguous targets. Native speech, UI, Keychain and Watch transport live under `App/`, outside the domain store; their acceptance requires native/device checks beyond these package tests.
