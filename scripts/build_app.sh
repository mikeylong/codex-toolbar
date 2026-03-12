#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexToolbar"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

is_module_cache_path_mismatch() {
  local log_file="$1"

  grep -Fq "PCH was compiled with module cache path" "$log_file" \
    && grep -Fq "missing required module 'SwiftShims'" "$log_file"
}

run_release_build_once() {
  local log_file="$1"

  : > "$log_file"
  swift build -c release 2>&1 | tee "$log_file"
}

build_release_binary() {
  local log_file
  log_file="$(mktemp -t codex-toolbar-build.XXXXXX.log)"
  trap 'rm -f "$log_file"' EXIT

  if run_release_build_once "$log_file"; then
    trap - EXIT
    rm -f "$log_file"
    return 0
  fi

  if ! is_module_cache_path_mismatch "$log_file"; then
    trap - EXIT
    rm -f "$log_file"
    return 1
  fi

  echo "Detected a stale Swift module cache after a repo move or rename." >&2
  echo "Running 'swift package clean' and retrying the release build once..." >&2
  swift package clean
  run_release_build_once "$log_file"

  trap - EXIT
  rm -f "$log_file"
}

cd "$ROOT_DIR"
build_release_binary
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/Codex.icns" "$RESOURCES_DIR/Codex.icns"
find "$BUILD_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$RESOURCES_DIR/" \;

chmod +x "$MACOS_DIR/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built app bundle:"
echo "$APP_DIR"
