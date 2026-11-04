#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/voice-check
swiftc -swift-version 6 App/Shared/SpeechVoiceSelection.swift App/Shared/CompanionState.swift Tests/NativeRuntime/SpeechVoiceChecks.swift -o .build/voice-check/SpeechVoiceChecks
.build/voice-check/SpeechVoiceChecks
