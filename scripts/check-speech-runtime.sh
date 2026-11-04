#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/speech-check
swiftc -swift-version 6 App/Shared/AudioPacketQueue.swift Tests/NativeRuntime/AudioQueueChecks.swift -o .build/speech-check/AudioQueueChecks
.build/speech-check/AudioQueueChecks
