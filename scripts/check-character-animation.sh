#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/character-check
swiftc App/Shared/CompanionState.swift App/Shared/CharacterStore.swift App/Shared/CharacterAnimationFrames.swift Tests/NativeRuntime/CharacterAnimationChecks.swift -o .build/character-check/CharacterAnimationChecks
.build/character-check/CharacterAnimationChecks
