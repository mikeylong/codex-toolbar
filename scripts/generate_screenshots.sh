#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCREENSHOTS_DIR="$ROOT_DIR/screenshots"
APP_EXECUTABLE="$ROOT_DIR/dist/CodexToolbar.app/Contents/MacOS/CodexToolbar"
README_SCENARIOS=(normal warning critical projection spark claude)

"$ROOT_DIR/scripts/build_app.sh" >/dev/null

mkdir -p "$SCREENSHOTS_DIR"

# Run this with the normal toolbar closed so duplicate menu bar items do not
# compete for their saved positions. The chooser preview never changes prefs.
CHOOSER_APP="$ROOT_DIR/dist/ProviderChooserCapture.app"
mkdir -p "$CHOOSER_APP/Contents/MacOS" "$CHOOSER_APP/Contents/Resources"
cat > "$CHOOSER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ProviderChooserCapture</string>
<key>CFBundleIdentifier</key><string>com.mikelong.codextoolbar.chooser-capture</string>
<key>CFBundleName</key><string>ProviderChooserCapture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Codex</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$ROOT_DIR/Resources/Codex.icns" "$CHOOSER_APP/Contents/Resources/Codex.icns"
swiftc "$ROOT_DIR/Sources/CodexToolbar/Models/UsageProvider.swift" \
  "$ROOT_DIR/Sources/CodexToolbar/Views/UsageProviderChooser.swift" \
  "$ROOT_DIR/scripts/capture_provider_chooser.swift" \
  -o "$CHOOSER_APP/Contents/MacOS/ProviderChooserCapture"
codesign --force --sign - "$CHOOSER_APP"

generated_files=()
for appearance in light dark; do
  for scenario in "${README_SCENARIOS[@]}"; do
    generated_files+=("$SCREENSHOTS_DIR/$scenario-$appearance-popover.png")
  done
done

generated_files+=(
  "$SCREENSHOTS_DIR/website-light-popover.png"
  "$SCREENSHOTS_DIR/website-dark-popover.png"
  "$SCREENSHOTS_DIR/normal-light-status-item.png"
  "$SCREENSHOTS_DIR/critical-dark-status-item.png"
)

for scenario in "${README_SCENARIOS[@]}"; do
  for appearance in light dark; do
    generated_files+=("$SCREENSHOTS_DIR/readme-$scenario-$appearance-popover.png")
  done
done

rm -f "${generated_files[@]}"

run_capture() {
  local scenario="$1"
  local appearance="$2"
  local capture_status_item="${3:-false}"

  CODEX_TOOLBAR_SCREENSHOT_VISIBLE_SUPPLEMENTAL_FAMILIES="codex_bengalfox" \
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
  for appearance in light dark; do
    cp "$SCREENSHOTS_DIR/$scenario-$appearance-popover.png" \
      "$SCREENSHOTS_DIR/readme-$scenario-$appearance-popover.png"
  done
done

for appearance in light dark; do
  run_capture "website" "$appearance"
  cp "$SCREENSHOTS_DIR/website-$appearance-popover.png" \
    "$ROOT_DIR/site/assets/codextoolbar-tahoe-$appearance.png"

  "$APP_EXECUTABLE" --screenshot-scenario providers \
    --screenshot-appearance "$appearance" --screenshot-output-dir "$SCREENSHOTS_DIR" \
    --screenshot-capture-status-item true --screenshot-capture-popover false \
    --screenshot-open-popover false
  chooser_image="$SCREENSHOTS_DIR/provider-chooser-$appearance.png"
  rm -f "$chooser_image"
  open -n -W "$CHOOSER_APP" --args "$appearance" "$chooser_image"
  [[ -s "$chooser_image" ]] || { echo "Chooser capture failed: $appearance" >&2; exit 1; }
  cp "$SCREENSHOTS_DIR/providers-$appearance-status-item.png" "$ROOT_DIR/site/assets/"
  cp "$chooser_image" "$ROOT_DIR/site/assets/"
  cp "$SCREENSHOTS_DIR/readme-claude-$appearance-popover.png" \
    "$ROOT_DIR/site/assets/claude-usage-$appearance.png"
done

echo "Generated screenshots:"
find "$SCREENSHOTS_DIR" -maxdepth 1 -name '*.png' -print | sort
