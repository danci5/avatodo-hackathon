# Shared Swift agent live integration

Verified on 2026-11-04, 10:07:12–10:07:28 UTC using the actual `AvatodoCore` Swift implementation and direct Meta HTTPS requests. This is live provider integration on macOS, separate from native simulator, microphone, paired Watch, or physical-device evidence.

- Model: `muse-spark-1.3`.
- Agent: `CompanionAgent` with `MetaClient` and `LocalTaskStore` using atomic JSON persistence.
- Seven model requests, 16.13 seconds total; seven checks passed.
- Fictional grocery data only. The fixture was deleted after the check.
- Development key read from macOS Keychain into process memory. No key, raw provider body, or authorization header was written to source, output, evidence, or logs.

Checks:

1. Ordinary conversational answer creates no notes.
2. Creates one checklist with unchecked milk, eggs and bread.
3. Repeating the same request UUID returns the saved outcome without duplicating the note.
4. A note-scoped correction changes milk to oat milk in that same note.
5. Checking off eggs and bread leaves oat milk unfinished.
6. The saved atomic snapshot matches the current note.
7. Local Undo restores the pre-completion items.

Reproduce deliberately (sends billable requests with fictional data):

```sh
swift run AvatodoProbe --run-live
```

Running `swift run AvatodoProbe` alone prints help and sends no requests. The probe requires the existing macOS development Keychain item configured by `scripts/configure-meta-key.command`; it does not install that key on an iPhone or Watch. It caps model requests at sixteen per invocation.

Machine-readable result: `artifacts/meta-swift-check/results.json` (ignored local artifact).
