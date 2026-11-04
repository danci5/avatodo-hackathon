# Avatodo implementation guidance

- Build only the current first release: native iPhone + paired Watch, companion creation, local notes/checklists and direct user-key Meta requests.
- Keep provider interfaces replaceable. The iPhone owns agent execution and calls Meta directly with the user's key.
- Use typed local actions and stable record IDs. Validate model-selected tools and base confirmations on committed results. Test retry handling, ambiguity, completion and undo.
- Store secrets in iPhone Keychain. No credentials in Watch transfers, fixtures, screenshots or logs.
- Preserve the same character across devices. Runtime states follow real capture, request and audio events. Cached/procedural motion must work without model requests.
- Use native SwiftUI previews when changing the interface, and verify the result in the app.
- Use isolated Avatodo build output, such as `.build` for Swift packages and `build/DerivedData` for app builds.
- Report source, tests, simulator, physical device and published release evidence separately. Never present design mockups or fixtures as a live model demo.
