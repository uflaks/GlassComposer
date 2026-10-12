#!/usr/bin/env bash
# Run the package tests on an iOS Simulator. `swift test` covers macOS only;
# UIKit-hosted tests (e.g. the composer hit-testing suite) run only here.
#
#   scripts/test-ios.sh                 # all test targets
#   SIMULATOR="iPhone 17e" scripts/test-ios.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${SIMULATOR:-$(xcrun simctl list devices available | grep -o 'iPhone [^(]*' | head -1 | sed 's/ *$//')}"
ONLY=()
if [ $# -gt 0 ]; then
  ONLY=(-only-testing:"$1")
fi

xcodebuild test \
  -scheme MaloryComposer \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  ${ONLY[@]+"${ONLY[@]}"} 2>&1 \
  | grep -E 'error:|warning: .*Tests/|✔|✘|↳|TEST (SUCCEEDED|FAILED)' | grep -v cachedGenerators
exit "${PIPESTATUS[0]}"
