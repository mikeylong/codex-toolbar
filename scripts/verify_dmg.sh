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

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/codextoolbar-dmg-mount.XXXXXX")"

cleanup() {
  /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
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

echo "Verified DMG:"
echo "$DMG_PATH"
