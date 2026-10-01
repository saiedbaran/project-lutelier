#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Install Xcode on a Mac to compile this iOS app.'; exit 1; }
xcodebuild -project Lutelier.xcodeproj -scheme Lutelier -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
# Set SIMULATOR_ID to a bootable installed iPhone simulator UUID to run tests.
if [ -n "${SIMULATOR_ID:-}" ]; then
  xcodebuild -project Lutelier.xcodeproj -scheme Lutelier -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
fi
