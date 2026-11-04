#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/character-check
swiftc App/Shared/CompanionState.swift App/Shared/CharacterStore.swift App/Shared/CharacterLibrary.swift Tests/NativeRuntime/CharacterLibraryChecks.swift -o .build/character-check/CharacterLibraryChecks
.build/character-check/CharacterLibraryChecks
