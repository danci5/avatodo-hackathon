# Local Meta development access

The current integration targets the direct [Meta Model API](https://dev.meta.ai/docs/models), including Muse Spark for language/tool requests and [Muse Image](https://dev.meta.ai/docs/image-generation) for character artwork. Actual account access and requests must be tested; a catalog entry alone is not proof that generation works.

Do not paste API keys into chats or commit them. For development on this Mac:

1. Open `scripts/configure-meta-key.command` in Terminal. Enter the key at its hidden password prompt. This stores it in macOS Keychain under service `app.avatodo.development.meta`, account `avatodo`; it replaces an existing item with the same identity.
2. Run `python3 scripts/check-meta-access.py`. It reads that one Keychain item and checks the direct Meta model catalog. Only status and availability of the expected model IDs are printed. Headers are passed through stdin; the key is not placed in command arguments or saved to a project file.
3. For the bounded live checks, run `python3 scripts/verify-meta-models.py --run-live --include-images`. These requests consume provider credits and use fictional notes. Omit `--include-images` for language/tool checks only. See [recorded access evidence](meta-access-evidence.md) for the checks already passed; the catalog helper does not perform them.

This Mac development credential is separate from the eventual iPhone Keychain setting. It does not synchronize to iPhone or Watch. The finished iPhone app must collect/store the user's own key securely; the Watch must never receive it. Do not claim app-level Meta integration based only on the development helper.
