# Local task engine

`AvatodoCore` is a pure Swift package with no model, UI, network or account dependency. It is the first implemented part of Avatodo; it is not an installable app.

Run the focused macOS tests with a compatible Swift 6 toolchain:

```sh
bash scripts/test.sh
```

The script keeps build and compiler caches inside the ignored `.build` directory.

## Supported operations

- Create, read, edit and delete notes, tasks and checklists.
- Append to a note, complete a task, add/rename/remove checklist items, and complete or reopen several items together.
- Undo a successful mutation if that record has not subsequently changed.
- Resolve an exact case-insensitive title, requiring clarification if multiple records match.

Every mutation carries a request ID. Replaying the same request returns its existing receipt; reusing that ID with a different payload fails. The receipt represents that historical mutation, not necessarily the current record. Consumers should fetch current state for display and avoid replaying celebrations or spoken confirmations for already handled request IDs.

Edits carry the revision last read by the agent. Stale edits fail rather than overwriting newer work. Checklist changes use item IDs, preserving identity when “milk” becomes “oat milk.” Multi-item requests are validated in full before any change. Deleted IDs and revisions remain reserved, including after undo.

## Durable writes

`LocalTaskStore` serializes mutations in one actor. It computes a candidate snapshot, saves it, then publishes the new state and receipt. A failed save throws, leaving in-memory state untouched. The persistence contract requires an all-or-nothing durable save of notes, revisions and receipts.

`JSONFilePersistence` is a development adapter using atomic file replacement. It supports reopening and retry receipts across process lifetimes. One store owns each file; cross-process or multiple-store writers are not supported. The native app's SwiftData adapter, application data-protection configuration, migrations and receipt retention remain integration work. Do not place user data in the repository.

Model-facing tools must translate their validated arguments into `TaskAction`; this enum is not a provider wire protocol. Model adapters, voice matching, Watch transport and UI are not implemented by this package.
