#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/character-check
swiftc -swift-version 6 App/Shared/CompanionState.swift App/Shared/CompanionMotion.swift Tests/NativeRuntime/CompanionMotionChecks.swift -o .build/character-check/CompanionMotionChecks
.build/character-check/CompanionMotionChecks
