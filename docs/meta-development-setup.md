# Local Meta development access

The direct Meta integration uses `muse-spark-1.3` for language/tool requests and `muse-image-1.0` for artwork. Users need their own enabled [Meta Model API](https://dev.meta.ai/docs/models) access. A catalog entry alone does not prove that requests work; provider usage charges may apply.

Do not paste keys into chats, source, shell command arguments or project files.

## iPhone app

Open Avatodo's **Settings**, enter your own key and choose **Save key**. It is stored in iPhone Keychain, with replacement/removal controls. The iPhone reads it for direct Meta requests; Watch payloads contain no key. See [native app setup](native-app.md).

## Mac checks

The Mac development item is separate from iPhone Keychain:

1. Run `zsh scripts/configure-meta-key.command` in Terminal. Enter the API key at the hidden password prompt, then enter it again. The prompt calls it a password because it is storing secret data; enter the Meta key, not the Mac login password. The helper stores/replaces service `app.avatodo.development.meta`, account `avatodo` in macOS Keychain and sends no request.
2. Run `python3 scripts/check-meta-access.py` for the model catalog. It prints status/model availability only; the key is read in memory and headers pass through stdin.
3. Run `swift run AvatodoProbe --run-live` deliberately for the real shared Swift agent/store integration check. It uses fictional notes, caps requests at sixteen and writes a sanitized result under ignored `artifacts/`. Running without `--run-live` prints help and sends no request. See [recorded live evidence](shared-swift-live-evidence.md).
4. `python3 scripts/verify-meta-models.py --run-live` retains the earlier fictional Python tool-fixture check. Add `--include-images` only when you intend to send image-generation/reference-edit requests. Those consume additional credits and are not required for the local unit checks. See [access evidence](meta-access-evidence.md).

The two live-check routes establish different evidence: the Swift probe exercises the real shared agent and store; the earlier fixture verifies API access and image endpoints. Neither alone proves the complete native app or Watch flow.

## Optional Debug simulator import

After installing a normally signed **Debug iPhone simulator** build, this explicit helper can import the saved Mac development key into that simulator's app Keychain:

```sh
python3 scripts/launch-development-simulator.py --simulator YOUR_BOOTED_IPHONE_SIMULATOR_UUID
```

Use the real UUID from `xcrun simctl list devices booted`; replace the placeholder rather than entering a key in the command. The helper verifies a booted iPhone simulator before reading the one development Keychain item. It launches `app.avatodo` with the key in child-process memory; the Debug simulator bootstrap saves it in simulator Keychain and clears its environment entry. It does not print the key or write a project credential file. Verify the saved-key status in the simulator's Settings.

The bootstrap is compiled only for Debug simulator builds. It is absent from physical-device and release builds and never supplies a key to Watch. A Mac development key does not automatically synchronize to any physical phone. Simulator Keychain still contains the imported secret until it is removed; remove it in Settings when finished with that simulator. Local machine access remains part of the development trust boundary.
