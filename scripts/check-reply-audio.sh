#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/voice-check
swiftc -swift-version 6 App/Shared/CompanionState.swift App/Shared/ReplyAudioWire.swift Tests/NativeRuntime/ReplyAudioChecks.swift -o .build/voice-check/ReplyAudioChecks
.build/voice-check/ReplyAudioChecks
