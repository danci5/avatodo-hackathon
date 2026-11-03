#!/bin/bash
set -euo pipefail
avatodo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$avatodo_root"
export CLANG_MODULE_CACHE_PATH="$avatodo_root/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$avatodo_root/.build/ModuleCache"
exec swift test \
  --scratch-path "$avatodo_root/.build" \
  --cache-path "$avatodo_root/.build/cache" \
  --config-path "$avatodo_root/.build/config" \
  --security-path "$avatodo_root/.build/security" "$@"
