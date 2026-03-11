# QuotaBar App Store Metadata

## Listing

- Name: `QuotaBar`
- Subtitle: `Menu bar usage monitor`
- Category: `Developer Tools`
- Primary language: `English (U.S.)`
- Pricing: `Free`
- Keywords: `menu bar, quota, usage, limits, developer, monitor, productivity, status`
- Promotional text: `See your coding-agent usage windows at a glance from the menu bar.`

## Description

QuotaBar shows your usage windows in the macOS menu bar, with a compact readout, reset timing, and a detailed popover for the most constrained windows.

QuotaBar is an independent macOS utility and is not affiliated with or endorsed by OpenAI.

Compatibility may be mentioned once in the long description and on the support site only after the live-sync path is App-Store-safe and approved.

## URLs

- Support URL: `https://github.com/mikeylong/codex-toolbar/tree/main/AppStore/site`
- Privacy Policy URL: `https://github.com/mikeylong/codex-toolbar/blob/main/AppStore/site/privacy.html`
- Marketing URL: `https://github.com/mikeylong/codex-toolbar/tree/main/AppStore/site`

## Current Release Blocker

- As of March 11, 2026, this repository does not include a documented, App-Store-safe live sync source for per-user ChatGPT/Codex usage windows.
- OpenAI's documented Usage API is organization-scoped and requires an admin API key. It does not expose the end-user usage-window data that QuotaBar is designed to display.
- OpenAI help documentation directs users to the limits/settings page for rate-limit details. It does not document a supported client API that QuotaBar can call directly from a sandboxed Mac App Store app.
- `Sources/QuotaBar/QuotaBarReleaseGate.swift` must remain closed until a documented API or another compliant architecture exists.

## Review Notes

- The current repository intentionally blocks App Store archive/release until `Sources/QuotaBar/QuotaBarReleaseGate.swift` marks live sync as available.
- For internal review and screenshot generation, use the `Demo scenario` submenu in the menu bar item’s right-click menu.
- Demo scenarios are deterministic and do not require signing in, another app, a shell, or terminal setup.
- If launch arguments are needed for QA, `--review-demo` enables the default demo scenario and `--review-demo-scenario <name>` accepts `normal`, `warning`, `critical`, `exhausted`, or `multiweek`.

## Export Compliance

- Encryption: standard Apple platform networking only, no custom cryptography
- Uses encryption: `Yes`
- Exempt from U.S. export compliance filing: `Likely yes`, subject to the final live-sync implementation

## Submission Gate

Do not submit while `QuotaBarReleaseGate.liveSyncAvailable` is `false`.
