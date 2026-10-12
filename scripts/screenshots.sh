#!/usr/bin/env bash
# Regenerate Screenshots/*.png from the Example app on an iOS Simulator.
# Needs xcodegen (brew install xcodegen). SIMULATOR overrides the device.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
BUNDLE=no.eidlaug.shots.ComposerShots
TMP="$(mktemp -d)"

swiftc -O -o "$TMP/crop" scripts/crop.swift
(cd Example/ComposerShots && xcodegen generate >/dev/null && xcodebuild \
  -project ComposerShots.xcodeproj -scheme ComposerShots \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath .derived CODE_SIGNING_ALLOWED=NO -quiet build)
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR" -b >/dev/null
xcrun simctl install booted Example/ComposerShots/.derived/Build/Products/Debug-iphonesimulator/ComposerShots.app

capture() { # <SHOT> <file>
  SIMCTL_CHILD_SHOT="$1" xcrun simctl launch --terminate-running-process booted "$BUNDLE" >/dev/null
  sleep 4
  xcrun simctl io booted screenshot --type=png "$TMP/$2.png" >/dev/null 2>&1
  "$TMP/crop" "$TMP/$2.png" "Screenshots/$2.png" 760
}
xcrun simctl ui booted appearance light
for shot in empty typed accessory sending recording error; do capture "$shot" "$shot"; done
xcrun simctl ui booted appearance dark
capture empty empty-dark
capture typed typed-dark
xcrun simctl ui booted appearance light
echo "Wrote $(ls Screenshots | wc -l | tr -d ' ') screenshots."
