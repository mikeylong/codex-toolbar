#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AppStore/QuotaBar.xcodeproj"
SCHEME="QuotaBar"
ARCHIVE_PATH="${1:-$ROOT_DIR/dist/QuotaBar.xcarchive}"

if ! rg -q 'static let liveSyncAvailable = true' "$ROOT_DIR/Sources/QuotaBar/QuotaBarReleaseGate.swift"; then
  echo "QuotaBar App Store archive blocked."
  echo "Set Sources/QuotaBar/QuotaBarReleaseGate.swift liveSyncAvailable to true only after implementing a documented, App-Store-safe live data source."
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Missing $PROJECT_PATH"
  echo "Run scripts/generate_quotabar_xcodeproj.rb first."
  exit 1
fi

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH"
