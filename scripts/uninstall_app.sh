#!/bin/zsh
set -euo pipefail

APP_NAME="CodexToolbar"
APP_BUNDLE_ID="com.mikelong.codextoolbar"
TARGET_APP="${HOME}/Applications/${APP_NAME}.app"
APP_EXECUTABLE="$TARGET_APP/Contents/MacOS/$APP_NAME"

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
  if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "Uninstall failed: app executable not found at $APP_EXECUTABLE" >&2
    exit 1
  fi

  if ! maintenance_output="$("$APP_EXECUTABLE" --maintenance-action unregister-login-item 2>&1)"; then
    if [[ -n "$maintenance_output" ]]; then
      echo "$maintenance_output" >&2
    fi
    echo "Uninstall failed: could not unregister launch at login." >&2
    exit 1
  fi

  rm -rf "$TARGET_APP"
  echo "Removed app bundle:"
  echo "$TARGET_APP"
else
  echo "App bundle not found:"
  echo "$TARGET_APP"
fi
