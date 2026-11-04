# Direct Meta access evidence — 4 November 2026

These are live API checks from a Mac using a development key stored in Keychain and fictional grocery data. They do not establish iPhone/Watch integration, durable app persistence or a finished agent.

| Check | Result | Requested model |
|---|---|---|
| Normal conversational reply | Passed; no note/tool call | muse-spark-1.3 |
| Create Grocery run with milk, eggs and bread | Passed; tool result returned before confirmation | muse-spark-1.3 |
| Follow-up correction: milk to oat milk | Passed; same fixture note and item identity | muse-spark-1.3 |
| Follow-up: check off eggs and bread | Passed; oat milk remained unfinished | muse-spark-1.3 |
| Lion artwork | Passed; decoded a valid 1600 × 1600 PNG | muse-image-1.0 |
| Reference-based speaking expression | Passed; decoded a valid 1600 × 1600 PNG | muse-image-1.0 |

The model-selected operations were validated against a small in-memory Python fixture. This is separate from the tested Swift task engine. Final production integration must use the app's typed tools and committed storage results.

Reproduce deliberately (uses provider credits):

```sh
python3 scripts/verify-meta-models.py --run-live --include-images
```

Omit `--include-images` for language/tool checks only. Fictional result summaries and generated images go to ignored `artifacts/meta-access-check/`. No credential is written there, and conversation history is not saved. Output remains development evidence rather than device latency or app demo evidence.

Artwork prompts produced both an illustration and later style candidates. The chosen design direction is a cute, polished stylized 3D companion. Local background preparation, expression alignment, state animation, asset packaging and Watch transfer remain to be implemented and verified. Speech, Keychain entry on iPhone and real paired-device operation are separate checks.
