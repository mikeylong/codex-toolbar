#!/bin/zsh
set -euo pipefail

APP_NAME="CodexToolbar"
APP_BUNDLE_ID="com.mikelong.codextoolbar"
TARGET_APP="${HOME}/Applications/${APP_NAME}.app"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

if [[ -d "$TARGET_APP" ]]; then
  rm -rf "$TARGET_APP"
  echo "Removed app bundle:"
  echo "$TARGET_APP"
else
  echo "App bundle not found:"
  echo "$TARGET_APP"
fi
