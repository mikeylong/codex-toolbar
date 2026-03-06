# CodexToolbar

A small macOS menu bar app that shows your Codex rate-limit remaining values.

## What It Does

- Shows the current `5h` and `Weekly` remaining percentages in the menu bar.
- Shows a popover with used/remaining percentages, progress bars, and reset timing.
- Refreshes automatically every 60 seconds.
- Supports manual refresh from the menu bar item's right-click menu.
- Can be installed as a real `.app` and configured to launch at login.

## Requirements

- macOS 14+
- Xcode Command Line Tools / Swift toolchain
- Codex installed and signed in on the same Mac

## Install

```bash
git clone https://github.com/mikeylong/codex-toolbar.git
cd codex-toolbar
./scripts/install_app.sh
```

That installs `CodexToolbar.app` to `~/Applications` and opens it.

## Use

- Left-click the menu bar item to see the current rate-limit status panel.
- Right-click the menu bar item for `Refresh now`, `Launch at login`, and `Quit`.
- Use `Launch at login` after running the installed app from `~/Applications`.

## Notes

- The app launches its own `codex app-server` subprocess. You do not need to keep an interactive Codex CLI session open.
- The displayed percentages are remaining percentages, matching the Codex UI.
- Auto-refresh syncs to system clock minute boundaries, so the numbers update at the start of each minute unless you refresh manually from the right-click menu.

## Development

```bash
swift test
swift run CodexToolbar
```
