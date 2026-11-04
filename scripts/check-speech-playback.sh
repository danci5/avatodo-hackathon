#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/voice-check
swiftc -swift-version 6 App/Shared/SpeechPlaybackMonitor.swift App/Shared/CompanionState.swift Tests/NativeRuntime/SpeechPlaybackChecks.swift -o .build/voice-check/SpeechPlaybackChecks
.build/voice-check/SpeechPlaybackChecks
