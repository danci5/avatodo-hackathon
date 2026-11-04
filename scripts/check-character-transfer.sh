#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/character-check
swiftc App/Shared/CompanionState.swift App/Shared/CharacterChunkAssembler.swift Tests/NativeRuntime/CharacterTransferChecks.swift -o .build/character-check/CharacterTransferChecks
.build/character-check/CharacterTransferChecks
