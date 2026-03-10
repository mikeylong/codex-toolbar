#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexToolbar"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_DIR="${HOME}/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME.app"
APP_EXECUTABLE="$TARGET_APP/Contents/MacOS/$APP_NAME"

"$ROOT_DIR/scripts/build_app.sh"

if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
  pkill -f "$APP_EXECUTABLE" >/dev/null 2>&1 || true
  sleep 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
fi

echo "Installed app bundle:"
echo "$TARGET_APP"

open "$TARGET_APP"
