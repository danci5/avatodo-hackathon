# Contributing

Avatodo is an independent iPhone/Watch project built during the Meta hackathon. Keep changes small and document what actually works.

The reviewed native design is now integrated into app source. Current priorities are completing direct Meta and speech/Watch behavior, validating persistence/failure recovery on the real supported setup, and proving the custom companion pipeline. The iPhone owns the local agent and notes. Do not add an application server, login service, subscription flow or remote MCP server as a prerequisite.

Start with [native app setup](docs/native-app.md), [architecture](docs/architecture.md) and [release evidence](docs/release-evidence.md). The included Xcode project builds from public files; change `project.yml` and regenerate with XcodeGen when altering project configuration. Use app-owned ignored build folders and normal simulator signing when checking Keychain.

Local checks:

```sh
bash scripts/test.sh
zsh scripts/check-audio-relay.sh
```

Live provider checks are explicitly opt-in and billable; use [secure development setup](docs/meta-development-setup.md). Never commit credentials, personal notes, raw audio or chat transcripts. Use clearly identified fictional data in tests and captures. Keep keys in Keychain and out of Watch payloads.

Validate failure cases that matter to a behavior change: interrupted saves, duplicate/lost requests, ambiguous targets, stale edits, expired sessions and unavailable paired phones. Report source, unit checks, live model calls, simulator, physical device and published release separately. A screenshot of a scripted fixture is not a working product recording.

Generated assets and dependencies require provenance and their applicable notices. Keep reduced motion, readable captions, long text, Dynamic Type, VoiceOver and touch targets usable while refining the native interface.
