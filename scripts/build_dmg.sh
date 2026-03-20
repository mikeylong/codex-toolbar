#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexToolbar"
DIST_DIR="$ROOT_DIR/dist"
SOURCE_APP="$DIST_DIR/$APP_NAME.app"
SOURCE_PLIST="$ROOT_DIR/Resources/Info.plist"
DMG_STAGING_DIR=""
VOLUME_STAGING_DIR=""
APP_STAGE_DIR=""

plist_value() {
  local plist_path="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path"
}

bool_env_true() {
  case "${1:l}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_distribution_signing() {
  if [[ -n "${REQUIRE_DISTRIBUTION_SIGNING:-}" ]]; then
    bool_env_true "${REQUIRE_DISTRIBUTION_SIGNING}"
    return $?
  fi

  bool_env_true "${CI:-false}"
}

should_verify_dmg_after_build() {
  if [[ -n "${VERIFY_DMG_AFTER_BUILD:-}" ]]; then
    bool_env_true "${VERIFY_DMG_AFTER_BUILD}"
    return $?
  fi

  if [[ "${CODE_SIGN_IDENTITY:--}" != "-" ]]; then
    return 0
  fi

  require_distribution_signing
}

notarization_is_configured() {
  [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]] \
    || [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]
}

validate_distribution_signing_config() {
  if ! require_distribution_signing; then
    return 0
  fi

  if [[ -z "${CODE_SIGN_IDENTITY:-}" || "${CODE_SIGN_IDENTITY:-}" == "-" ]]; then
    echo "REQUIRE_DISTRIBUTION_SIGNING is enabled, but CODE_SIGN_IDENTITY is missing or ad hoc ('-')." >&2
    exit 1
  fi

  if ! notarization_is_configured; then
    echo "REQUIRE_DISTRIBUTION_SIGNING is enabled, but Apple notarization credentials are not configured." >&2
    exit 1
  fi
}

sign_path() {
  local path="$1"
  local identity="${CODE_SIGN_IDENTITY:--}"
  local -a args=(--force --sign "$identity")

  if [[ "$identity" != "-" ]]; then
    args+=(--timestamp --options runtime)
  fi

  /usr/bin/codesign "${args[@]}" "$path"
}

notarize_path_if_configured() {
  local path="$1"
  local submit_path="$path"
  local archive_path=""

  if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
    local -a args=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")

    if [[ -n "${NOTARYTOOL_KEYCHAIN:-}" ]]; then
      args+=(--keychain "$NOTARYTOOL_KEYCHAIN")
    fi

    if [[ -d "$path" && "$path" == *.app ]]; then
      archive_path="$(/usr/bin/mktemp "$DIST_DIR/notary-submit.XXXXXX")"
      /bin/rm -f "$archive_path"
      archive_path="$archive_path.zip"
      /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$path" "$archive_path"
      submit_path="$archive_path"
    fi

    /usr/bin/xcrun notarytool submit "$submit_path" "${args[@]}" --wait
    /usr/bin/xcrun stapler staple "$path"

    if [[ -n "$archive_path" ]]; then
      /bin/rm -f "$archive_path"
    fi
    return 0
  fi

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    /usr/bin/xcrun notarytool submit \
      "$path" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
    /usr/bin/xcrun stapler staple "$path"
    return 0
  fi

  echo "Skipping notarization for $path because Apple notarization credentials are not configured." >&2
}

cleanup() {
  [[ -n "$DMG_STAGING_DIR" ]] && rm -rf "$DMG_STAGING_DIR"
}

trap cleanup EXIT

mkdir -p "$DIST_DIR"
DMG_STAGING_DIR="$(/usr/bin/mktemp -d "$DIST_DIR/codextoolbar-dmg.XXXXXX")"
VOLUME_STAGING_DIR="$DMG_STAGING_DIR/volume"
APP_STAGE_DIR="$VOLUME_STAGING_DIR/$APP_NAME.app"
validate_distribution_signing_config
"$ROOT_DIR/scripts/build_app.sh"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app bundle is missing: $SOURCE_APP" >&2
  exit 1
fi

APP_VERSION="$(plist_value "$SOURCE_PLIST" CFBundleShortVersionString)"
VOLUME_NAME="$APP_NAME $APP_VERSION"
DMG_BASENAME="$APP_NAME-$APP_VERSION"
TEMP_DMG="$DIST_DIR/$DMG_BASENAME.temp.dmg"
FINAL_DMG="$DIST_DIR/$DMG_BASENAME.dmg"

rm -rf "$VOLUME_STAGING_DIR"
mkdir -p "$VOLUME_STAGING_DIR"
cp -R "$SOURCE_APP" "$APP_STAGE_DIR"
ln -s /Applications "$VOLUME_STAGING_DIR/Applications"

sign_path "$APP_STAGE_DIR"
notarize_path_if_configured "$APP_STAGE_DIR"

rm -f "$TEMP_DMG" "$FINAL_DMG"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$VOLUME_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$TEMP_DMG"

mv "$TEMP_DMG" "$FINAL_DMG"
sign_path "$FINAL_DMG"
notarize_path_if_configured "$FINAL_DMG"

if should_verify_dmg_after_build; then
  "$ROOT_DIR/scripts/verify_dmg.sh" "$FINAL_DMG"
fi

echo "Built DMG:"
echo "$FINAL_DMG"
