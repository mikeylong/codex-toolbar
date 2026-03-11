#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="$ROOT_DIR/AppStore/raw-screenshots"
OUTPUT_DIR="$ROOT_DIR/AppStore/screenshots"

cd "$ROOT_DIR"
swift build -c release --product QuotaBar >/dev/null
BUILD_DIR="$(swift build -c release --show-bin-path)"
APP_EXECUTABLE="$BUILD_DIR/QuotaBar"

mkdir -p "$RAW_DIR" "$OUTPUT_DIR"
find "$RAW_DIR" -maxdepth 1 -name '*.png' -delete
find "$OUTPUT_DIR" -maxdepth 1 -name '*.png' -delete

run_capture() {
  local scenario="$1"
  local capture_status_item="${2:-false}"

  QUOTABAR_SCREENSHOT_SCENARIO="$scenario" \
  QUOTABAR_SCREENSHOT_APPEARANCE="light" \
  QUOTABAR_SCREENSHOT_OUTPUT_DIR="$RAW_DIR" \
  QUOTABAR_SCREENSHOT_CAPTURE_POPOVER="true" \
  QUOTABAR_SCREENSHOT_CAPTURE_STATUS_ITEM="$capture_status_item" \
  QUOTABAR_SCREENSHOT_OPEN_POPOVER="true" \
  "$APP_EXECUTABLE"
}

run_capture normal true
run_capture warning false
run_capture critical false
run_capture multiweek false

swift scripts/render_quotabar_marketing_screenshots.swift

echo "Generated:"
find "$OUTPUT_DIR" -maxdepth 1 -name '*.png' -print | sort
