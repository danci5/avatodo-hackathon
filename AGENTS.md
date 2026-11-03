# Avatodo implementation guidance

- Build only the current first release: native iPhone + paired Watch, companion creation, local notes/checklists and direct user-key Meta requests.
- Keep provider interfaces replaceable, but do not implement future local models, remote MCP hosting or external-assistant handoff as release dependencies.
- Keep private strategy in the sibling `avatodo-business` repository. Do not copy its planning archive into this repository.
- Use typed local actions and stable record IDs. Validate model-selected tools and base confirmations on committed results. Test retry handling, ambiguity, completion and undo.
- Store secrets in iPhone Keychain. No credentials in Watch transfers, fixtures, screenshots or logs.
- Preserve the same character across devices. Runtime states follow real capture, request and audio events. Cached/procedural motion must work without model requests.
- Follow the agreed Figma review before implementing the product UI. Non-UI domain and integration experiments may proceed independently.
- Use isolated Avatodo build output, such as `.build` for Swift packages and `build/DerivedData` for app builds.
- Report source, tests, simulator, physical device and published release evidence separately. Never present design mockups or fixtures as a live model demo.
