#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexToolbar"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_DIR="${HOME}/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME.app"
APP_EXECUTABLE="$TARGET_APP/Contents/MacOS/$APP_NAME"

plist_value() {
  local plist_path="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path"
}

verify_installed_version_matches_source() {
  local source_plist="$ROOT_DIR/Resources/Info.plist"
  local installed_plist="$TARGET_APP/Contents/Info.plist"
  local source_short_version installed_short_version
  local source_bundle_version installed_bundle_version

  source_short_version="$(plist_value "$source_plist" CFBundleShortVersionString)"
  installed_short_version="$(plist_value "$installed_plist" CFBundleShortVersionString)"
  source_bundle_version="$(plist_value "$source_plist" CFBundleVersion)"
  installed_bundle_version="$(plist_value "$installed_plist" CFBundleVersion)"

  if [[ "$source_short_version" != "$installed_short_version" || "$source_bundle_version" != "$installed_bundle_version" ]]; then
    echo "Installed app version mismatch." >&2
    echo "Source Info.plist: version $source_short_version ($source_bundle_version)" >&2
    echo "Installed app bundle: version $installed_short_version ($installed_bundle_version)" >&2
    return 1
  fi
}

"$ROOT_DIR/scripts/build_app.sh"

if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
  pkill -f "$APP_EXECUTABLE" >/dev/null 2>&1 || true
  sleep 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
verify_installed_version_matches_source

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
fi

echo "Installed app bundle:"
echo "$TARGET_APP"

open "$TARGET_APP"
