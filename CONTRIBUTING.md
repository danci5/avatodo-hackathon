# Contributing

The project is being built independently during the Meta hackathon. Keep changes small and document what actually works.

Current implementation priorities are the local task domain, direct Meta integration, paired-device interaction and character preparation. UI implementation follows review of the shared iPhone and Watch designs.

Do not add an application server, login service, subscription flow or remote MCP server as a prerequisite. Never commit credentials or personal notes. Use clearly identified fictional data in screenshots and tests.

For behavior changes, validate the failure cases that matter: an interrupted save, a duplicate request, an ambiguous list, a stale edit and an unavailable paired phone. Include reproducible evidence with a change. Generated assets and dependencies require recorded provenance and their applicable license.
