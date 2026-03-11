# QuotaBar App Store Surface

This directory contains the macOS App Store packaging surface for `QuotaBar`, the independent App Store SKU for this repository.

## Contents

- `Config/QuotaBar-Info.plist`: App Store app bundle metadata
- `Config/QuotaBar.entitlements`: sandbox entitlement set
- `Resources/PrivacyInfo.xcprivacy`: privacy manifest
- `Resources/QuotaBar.icns`: App Store icon
- `site/`: support and privacy pages that can be published directly from the repo
- `AppStoreConnect.md`: App Store Connect metadata, review notes, and submission copy

## Release Gate

Do not submit or archive the App Store build until `Sources/QuotaBar/QuotaBarReleaseGate.swift` sets `liveSyncAvailable` to `true` and the QuotaBar client is backed by a documented, permitted live data source.

Use `scripts/archive_quotabar_app_store.sh` for release archives. That script enforces the gate before calling `xcodebuild archive`.
