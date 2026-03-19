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

persist_git_update_metadata() {
  local source_plist="$ROOT_DIR/Resources/Info.plist"
  local bundle_identifier upstream remote_name branch_name

  bundle_identifier="$(plist_value "$source_plist" CFBundleIdentifier)"
  upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  remote_name="origin"
  branch_name="main"

  if [[ "$upstream" == */* ]]; then
    remote_name="${upstream%%/*}"
    branch_name="${upstream#*/}"
  fi

  defaults write "$bundle_identifier" "gitUpdate.repositoryRoot" -string "$ROOT_DIR"
  defaults write "$bundle_identifier" "gitUpdate.remoteName" -string "$remote_name"
  defaults write "$bundle_identifier" "gitUpdate.branchName" -string "$branch_name"
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
persist_git_update_metadata

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
fi

echo "Installed app bundle:"
echo "$TARGET_APP"

open "$TARGET_APP"
