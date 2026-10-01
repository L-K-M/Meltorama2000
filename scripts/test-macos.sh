#!/usr/bin/env bash
# Runs native document, input, GPU replay, session, and export unit tests.
# GPU tests explicitly skip if no accelerated Mac context is available.
#
# Usage: scripts/test-macos.sh [--smoke]
# --smoke also builds the dist bundle and exercises its GPU/save pipeline.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "$0"; exit 0; fi
if [[ $# -gt 1 ]] || [[ $# -eq 1 && "$1" != "--smoke" ]]; then
  echo "!! usage: scripts/test-macos.sh [--smoke]" >&2
  exit 1
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/meltorama-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
echo "==> Checking shared shader translation"
python3 scripts/sync-macos-shaders.py --check
echo "==> Running native tests"
swift test --package-path macos --disable-sandbox
if [[ "${1:-}" == "--smoke" ]]; then
  scripts/build-macos.sh
  dist/Meltorama.app/Contents/MacOS/Meltorama --smoke-test
fi
