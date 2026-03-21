#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

TAG="$1"
if [[ ! "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Expected tag like v0.1.8, got: $TAG" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_INDEX="$ROOT_DIR/site/index.html"
DMG_NAME="CodexToolbar-${TAG#v}.dmg"
DMG_URL="https://github.com/mikeylong/codex-toolbar/releases/download/$TAG/$DMG_NAME"
RELEASE_URL="https://github.com/mikeylong/codex-toolbar/releases/tag/$TAG"

perl -0pi -e 's@href="https://github\.com/mikeylong/codex-toolbar/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/CodexToolbar-[0-9]+\.[0-9]+\.[0-9]+\.dmg"@href="'"$DMG_URL"'"@g' "$SITE_INDEX"
perl -0pi -e 's@href="https://github\.com/mikeylong/codex-toolbar/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+"@href="'"$RELEASE_URL"'"@g' "$SITE_INDEX"
perl -0pi -e 's@>v[0-9]+\.[0-9]+\.[0-9]+ \(Latest\)<@>'"$TAG"' (Latest)<@g' "$SITE_INDEX"
