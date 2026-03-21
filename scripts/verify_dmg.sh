#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/App.dmg" >&2
  exit 1
fi

DMG_PATH="$1"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

fail() {
  echo "$1" >&2
  exit 1
}

codesign_details() {
  /usr/bin/codesign -dv --verbose=4 "$1" 2>&1
}

assert_non_adhoc_signature() {
  local path="$1"
  local label="$2"
  local details

  if ! details="$(codesign_details "$path")"; then
    fail "$label is not codesigned: $path"
  fi

  if [[ "$details" == *"Signature=adhoc"* ]]; then
    fail "$label is ad hoc signed: $path"
  fi

  if [[ "$details" == *"TeamIdentifier=not set"* ]]; then
    fail "$label is missing a TeamIdentifier: $path"
  fi
}

validate_stapled_ticket() {
  local path="$1"
  local label="$2"

  if ! /usr/bin/xcrun stapler validate "$path" >/dev/null 2>&1; then
    fail "$label does not have a valid stapled notarization ticket: $path"
  fi
}

assert_gatekeeper_accepts_dmg() {
  local path="$1"

  if ! /usr/sbin/spctl -a -vv --type open --context context:primary-signature "$path" >/dev/null 2>&1; then
    fail "Gatekeeper rejected the DMG: $path"
  fi
}

assert_gatekeeper_accepts_app() {
  local path="$1"

  if ! /usr/sbin/spctl -a -vv -t exec "$path" >/dev/null 2>&1; then
    fail "Gatekeeper rejected the app bundle inside the DMG: $path"
  fi
}

run_packaged_app_smoke_test() {
  local app_path="$1"
  local executable_path="$app_path/Contents/MacOS/CodexToolbar"
  local diagnostics_path="$SMOKE_TEST_DIR/startup-diagnostics.json"
  local stdout_log="$SMOKE_TEST_DIR/stdout.log"
  local stderr_log="$SMOKE_TEST_DIR/stderr.log"
  local app_pid=""
  local exit_code=0
  local waited_seconds=0

  if [[ ! -x "$executable_path" ]]; then
    fail "App executable is missing or not executable: $executable_path"
  fi

  "$executable_path" \
    --screenshot-scenario normal \
    --screenshot-capture-popover false \
    --screenshot-capture-status-item false \
    --screenshot-open-popover false \
    --startup-diagnostics-output "$diagnostics_path" \
    --startup-diagnostics-exit true \
    >"$stdout_log" 2>"$stderr_log" &
  app_pid="$!"

  while kill -0 "$app_pid" >/dev/null 2>&1; do
    if [[ -s "$diagnostics_path" ]]; then
      break
    fi

    if (( waited_seconds >= 20 )); then
      kill "$app_pid" >/dev/null 2>&1 || true
      wait "$app_pid" >/dev/null 2>&1 || true
      fail "Packaged app smoke test timed out before writing startup diagnostics: $app_path"
    fi

    sleep 1
    (( waited_seconds += 1 ))
  done

  if ! wait "$app_pid"; then
    exit_code=$?
    fail "Packaged app smoke test exited with status $exit_code: $app_path"
  fi

  if [[ ! -s "$diagnostics_path" ]]; then
    fail "Packaged app smoke test did not write startup diagnostics: $app_path"
  fi

  if ! /usr/bin/python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$diagnostics_path" >/dev/null 2>&1; then
    fail "Packaged app smoke test wrote invalid startup diagnostics JSON: $diagnostics_path"
  fi
}

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/codextoolbar-dmg-mount.XXXXXX")"
SMOKE_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codextoolbar-dmg-smoke.XXXXXX")"

cleanup() {
  /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  rm -rf "$SMOKE_TEST_DIR" >/dev/null 2>&1 || true
}

trap cleanup EXIT

assert_non_adhoc_signature "$DMG_PATH" "DMG"
validate_stapled_ticket "$DMG_PATH" "DMG"
assert_gatekeeper_accepts_dmg "$DMG_PATH"

/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" -quiet

app_candidates=("$MOUNT_POINT"/*.app(N))

if (( ${#app_candidates[@]} != 1 )); then
  fail "Expected exactly one app bundle inside the DMG, found ${#app_candidates[@]}."
fi

APP_PATH="$app_candidates[1]"

assert_non_adhoc_signature "$APP_PATH" "App bundle"
validate_stapled_ticket "$APP_PATH" "App bundle"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
  fail "codesign verification failed for the app bundle inside the DMG: $APP_PATH"
fi

assert_gatekeeper_accepts_app "$APP_PATH"
run_packaged_app_smoke_test "$APP_PATH"

echo "Verified DMG:"
echo "$DMG_PATH"
