# Local Meta development access

The direct Meta integration uses `muse-spark-1.3` for language/tool requests and `muse-image-1.0` for artwork. Users need their own enabled [Meta Model API](https://dev.meta.ai/docs/models) access. A catalog entry alone does not prove that requests work; provider usage charges may apply.

Do not paste keys into chats, source, shell command arguments or project files. Meta features require users aged 18 or older and affirmative in-app permission. [Meta Model API Terms §3.1](https://dev.meta.ai/legal/terms-of-service) require prior written permission to share a key with a third party; an Apple reviewer or another tester must not be given the existing development key. Establish a legitimate provider-approved review route before external Beta Review. Local note editing and the default companion do not provide a substitute demonstration of live model behavior.

## iPhone app

Open Avatodo's **Settings**, enter your own key and choose **Save key**, then review **Data sharing with Meta** and explicitly allow requests. Build 2 requires fresh permission for its updated 18+ notice. The key is stored in iPhone Keychain, with replacement/removal controls. Saving confirms storage only. In build 3, choose **Check connection** to authenticate against the model catalog without sending notes or generating content. A listed model does not prove that inference or image creation will succeed. HTTP 401 means the key was rejected; HTTP 403 means Meta denied the request, which can involve account/model permissions or the network. The iPhone reads the key for direct Meta requests; Watch payloads contain no key. See [native app setup](native-app.md).

### Copying your own development key to iPhone

If you already saved your own key in Mac Keychain, select its item in **Keychain Access** and choose **Copy Password to Clipboard**. Generic Copy can copy the item’s name instead of its secret value; **Show Password** is not required for this copy action. Complete any macOS authentication prompt yourself, then paste directly into Avatodo’s secure key field on the actual iPhone and choose Save/Replace key.

For [Universal Clipboard](https://support.apple.com/en-nz/102430), keep the Mac and iPhone nearby, signed in to the same Apple Account, with Wi-Fi, Bluetooth and Handoff enabled. The Mac development Keychain item is not automatically synchronized to Avatodo’s iPhone Keychain.

Choose **Check connection** after saving. “Key accepted; Muse Spark and Muse Image are listed” verifies catalog authentication for the phone’s stored key. Then try a separate **Talk → Done** request to verify actual reasoning and voice. A catalog pass alone does not verify speech, inference, a saved note or Watch operation.

On 4 November 2026, the owner reported HTTP 401 on the actual iPhone, then confirmed both required models were listed after replacing the saved value using the copy/paste steps above. That is a user-reported catalog-authentication pass; a complete Talk/Done response and saved-note test remain pending. No key value was read out or added to the release.

## Mac checks

The Mac development item is separate from iPhone Keychain:

1. Run `zsh scripts/configure-meta-key.command` in Terminal. Enter the API key at the hidden password prompt, then enter it again. The prompt calls it a password because it is storing secret data; enter the Meta key, not the Mac login password. The helper stores/replaces service `app.avatodo.development.meta`, account `avatodo` in macOS Keychain and sends no request.
2. Run `swift run AvatodoProbe --check-access` to check catalog authentication with the production Swift client, without notes or inference. It prints status/model availability only. The earlier `python3 scripts/check-meta-access.py` catalog check remains available; its key is read in memory and headers pass through stdin.
3. Run `swift run AvatodoProbe --run-live` deliberately for the real shared Swift agent/store integration check. It uses fictional notes, caps requests at sixteen and writes a sanitized result under ignored `artifacts/`. Running without an explicit `--run-live` or `--check-access` flag prints help and sends no request. See [recorded live evidence](shared-swift-live-evidence.md).
4. `python3 scripts/verify-meta-models.py --run-live` retains the earlier fictional Python tool-fixture check. Add `--include-images` only when you intend to send image-generation/reference-edit requests. Those consume additional credits and are not required for the local unit checks. See [access evidence](meta-access-evidence.md).

The two live-check routes establish different evidence: the Swift probe exercises the real shared agent and store; the earlier fixture verifies API access and image endpoints. Neither alone proves the complete native app or Watch flow.

## Optional Debug simulator import

After installing a normally signed **Debug iPhone simulator** build, this explicit helper can import the saved Mac development key into that simulator's app Keychain:

```sh
python3 scripts/launch-development-simulator.py --simulator YOUR_BOOTED_IPHONE_SIMULATOR_UUID
```

Use the real UUID from `xcrun simctl list devices booted`; replace the placeholder rather than entering a key in the command. The helper verifies a booted iPhone simulator before reading the one development Keychain item. It launches `app.avatodo` with the key in child-process memory; the Debug simulator bootstrap saves it in simulator Keychain and clears its environment entry. It does not print the key or write a project credential file. Verify the saved-key status in the simulator's Settings.

The bootstrap is compiled only for Debug simulator builds. It is absent from physical-device and release builds and never supplies a key to Watch. A Mac development key does not automatically synchronize to any physical phone. Simulator Keychain still contains the imported secret until it is removed; remove it in Settings when finished with that simulator. Local machine access remains part of the development trust boundary.
