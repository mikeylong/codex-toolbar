#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexToolbar"
TARGET_DIR="${HOME}/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME.app"
APP_EXECUTABLE="$TARGET_APP/Contents/MacOS/$APP_NAME"
DIAGNOSTICS_DIR="${TMPDIR:-/tmp}/codex-toolbar-smoke-test"
DIAGNOSTICS_FILE="$DIAGNOSTICS_DIR/startup.json"
TIMEOUT_SECONDS="${CODEX_TOOLBAR_SMOKE_TIMEOUT_SECONDS:-15}"

cleanup() {
  if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
    pkill -f "$APP_EXECUTABLE" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

rm -rf "$DIAGNOSTICS_DIR"
mkdir -p "$DIAGNOSTICS_DIR"

rm -rf "$TARGET_APP"
"$ROOT_DIR/scripts/install_app.sh" >/dev/null

if [[ ! -d "$TARGET_APP" ]]; then
  echo "Smoke test failed: installed app bundle not found at $TARGET_APP" >&2
  exit 1
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Smoke test failed: installed app executable not found at $APP_EXECUTABLE" >&2
  exit 1
fi

cleanup

CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_OUTPUT="$DIAGNOSTICS_FILE" \
CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_EXIT="true" \
open -n "$TARGET_APP"

elapsed=0
while (( elapsed < TIMEOUT_SECONDS )); do
  if [[ -f "$DIAGNOSTICS_FILE" ]]; then
    break
  fi

  sleep 1
  (( elapsed += 1 ))
done

if [[ ! -f "$DIAGNOSTICS_FILE" ]]; then
  echo "Smoke test failed: no startup diagnostics written within ${TIMEOUT_SECONDS}s" >&2
  exit 1
fi

python3 - "$DIAGNOSTICS_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

state = data.get("state", "")
status_message = data.get("statusMessage", "")
card_count = int(data.get("cardCount", 0))
is_valid = (
    (state == "ready" and card_count > 0) or
    (state == "error" and status_message in {
        "Codex CLI not found.",
        "Sign in to Codex to view rate limits.",
        "No rate-limit data available."
    })
)

if not data.get("launched", False):
    print("Smoke test failed: app did not report launched=true", file=sys.stderr)
    sys.exit(1)

if not is_valid:
    print("Smoke test failed: invalid first-run state", file=sys.stderr)
    print(json.dumps(data, indent=2, sort_keys=True), file=sys.stderr)
    sys.exit(1)

print("Smoke test passed.")
print(json.dumps(data, indent=2, sort_keys=True))
PY
