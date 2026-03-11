#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCREENSHOTS_DIR="$ROOT_DIR/screenshots"
APP_EXECUTABLE="$ROOT_DIR/dist/CodexToolbar.app/Contents/MacOS/CodexToolbar"
README_SCENARIOS=(normal warning critical)

"$ROOT_DIR/scripts/build_app.sh" >/dev/null

mkdir -p "$SCREENSHOTS_DIR"
find "$SCREENSHOTS_DIR" -maxdepth 1 -name '*.png' -delete

run_capture() {
  local scenario="$1"
  local appearance="$2"
  local capture_status_item="${3:-false}"

  CODEX_TOOLBAR_SCREENSHOT_SCENARIO="$scenario" \
  CODEX_TOOLBAR_SCREENSHOT_APPEARANCE="$appearance" \
  CODEX_TOOLBAR_SCREENSHOT_OUTPUT_DIR="$SCREENSHOTS_DIR" \
  CODEX_TOOLBAR_SCREENSHOT_CAPTURE_POPOVER="true" \
  CODEX_TOOLBAR_SCREENSHOT_CAPTURE_STATUS_ITEM="$capture_status_item" \
  CODEX_TOOLBAR_SCREENSHOT_OPEN_POPOVER="true" \
  "$APP_EXECUTABLE"
}

for appearance in light dark; do
  for scenario in "${README_SCENARIOS[@]}"; do
    capture_status_item="false"

    if [[ "$scenario" == "normal" && "$appearance" == "light" ]]; then
      capture_status_item="true"
    fi

    if [[ "$scenario" == "critical" && "$appearance" == "dark" ]]; then
      capture_status_item="true"
    fi

    run_capture "$scenario" "$appearance" "$capture_status_item"
  done
done

for scenario in "${README_SCENARIOS[@]}"; do
  cp "$SCREENSHOTS_DIR/$scenario-light-popover.png" \
    "$SCREENSHOTS_DIR/readme-$scenario-light-popover.png"
done

echo "Generated screenshots:"
find "$SCREENSHOTS_DIR" -maxdepth 1 -name '*.png' -print | sort
