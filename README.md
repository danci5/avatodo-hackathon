# Avatodo

A personalized companion for iPhone and Apple Watch, demonstrated with a task agent.

**Status: early development.** Repository setup and design work are in progress. There is no released iPhone or Watch app yet. Planned features below are not claims of working behavior.

## First release

- Describe your companion by voice or text. Muse Image generates artwork; the app prepares a small animation package on iPhone and transfers it to Watch.
- Talk to the same companion on either device.
- Create and edit notes, tasks and checklists stored on the iPhone. Check off items by voice and undo mistakes.
- Supply your own Meta API key. The iPhone calls Meta directly and executes validated local actions; there is no Avatodo agent server to host.

Image generation and language reasoning require internet and provider access. Animation playback and stored notes are local. Model output is treated as a request to act; the app confirms only successful storage changes.

## Getting started

The planned native app targets iOS/watchOS 27. Building and installing on hardware will require a compatible Xcode version, Apple signing, a paired iPhone/Watch, and your own enabled Meta account. Exact supported devices and setup instructions will be published after physical-device verification. Do not assume cloning this repository installs a Watch app automatically.

See [architecture](docs/architecture.md), [contributing](CONTRIBUTING.md), and [release evidence](docs/release-evidence.md).

## Privacy and source ownership

API keys belong in iPhone Keychain, never source, logs or Watch assets. Requests send relevant user text or character descriptions to the chosen model provider. Local storage does not mean cloud inference is offline or that provider retention is zero.

App source is Apache-2.0; provider services, model weights, fonts and generated assets retain their own terms. No affiliation with Apple, Meta or Ray-Ban is implied.
