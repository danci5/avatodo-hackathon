#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/audio-check
swiftc App/Shared/RelayPCMEncoder.swift Tests/NativeRuntime/AudioRelayChecks.swift -o .build/audio-check/AudioRelayChecks
.build/audio-check/AudioRelayChecks
