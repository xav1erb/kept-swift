#!/usr/bin/env bash
# THE ONE SIGNAL (LOOP.md): exit 0 = green. Anything else is red — nothing in between.
# Regenerates the project, builds, and runs the full test suite on the pinned simulator.
# A green bought by weakening a contract or a test is a red.
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${GREENLIGHT_SIM:-iPhone 17 Pro}"
LOG_DIR=".loop"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/greenlight-$(date +%Y%m%d-%H%M%S).log"

{
  xcodegen generate
  xcodebuild \
    -project Kept.xcodeproj \
    -scheme Kept \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    test
} 2>&1 | tee "$LOG"

echo "GREEN — log: $(pwd)/$LOG"
