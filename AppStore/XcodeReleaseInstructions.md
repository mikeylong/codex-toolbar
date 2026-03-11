# QuotaBar App Store Release Instructions For Xcode

Use these instructions when continuing the Mac App Store release work in Xcode.

## Objective

Continue the App Store release path for `QuotaBar`, the sandboxed Mac App Store SKU in this repository. Keep the direct-download `CodexToolbar` path intact. Do not submit or archive for App Store release until the live data source is App-Store-safe and `QuotaBarReleaseGate.liveSyncAvailable` is intentionally changed to `true`.

## Open And Work In

- Open `AppStore/QuotaBar.xcodeproj` in Xcode.
- Use the `QuotaBar` scheme.
- Treat `Sources/QuotaBar` and shared `Sources/ToolbarCore` code as the main implementation surface.
- Avoid changing the direct-download CLI integration in `Sources/CodexToolbarApp` unless a shared nonbreaking refactor is required.

## Current State

- `QuotaBar` is already split from the direct-download app and has independent branding.
- The App Store target already has a sandbox entitlement file, privacy manifest, icon, support site files, and screenshot assets.
- `QuotaBarRateLimitClient` is demo-only today and does not use `Process()` or path probing.
- `QuotaBarReviewDemo` supports deterministic review/demo scenarios for App Review and screenshots.
- Submission is intentionally blocked by `Sources/QuotaBar/QuotaBarReleaseGate.swift`.

## Hard Constraints

- Do not add any dependency on a user-installed `codex` executable.
- Do not use `Process()` or shell execution in the `QuotaBar` App Store path.
- Do not add OpenAI or Codex branding to the QuotaBar app name, icon, screenshots, or in-app marketing copy.
- Keep the app functional in a clean macOS account with no terminal setup and no companion app installed.
- Preserve demo/review mode so App Review can exercise the app without external setup.

## Primary Task

Implement a documented, permitted, App-Store-safe live sync source for QuotaBar.

Expected behavior:

- `QuotaBarRateLimitClient` should fetch real account and rate-limit data without launching external executables.
- The client should continue to support deterministic demo scenarios when review mode is enabled.
- Offline, auth, and unavailable states should surface clear user-facing messages.
- Once the live source is complete and verified, change `QuotaBarReleaseGate.liveSyncAvailable` from `false` to `true`.

If no compliant live source can be implemented from documented APIs or allowed app architecture, stop there and document the blocker instead of weakening the App Store constraints.

## Secondary Tasks

1. Verify Xcode signing and bundle configuration.
   - Confirm bundle identifier is `com.mikelong.quotabar`.
   - Set the Apple Developer team in the Xcode project.
   - Confirm version and build values are correct for the first App Store submission.

2. Verify App Sandbox and privacy metadata.
   - Review `AppStore/Config/QuotaBar.entitlements`.
   - Review `AppStore/Resources/PrivacyInfo.xcprivacy`.
   - Add only the minimum entitlements required by the final live-sync design.

3. Keep App Review support intact.
   - Preserve the `Demo scenario` menu in the status item right-click menu.
   - Keep launch-argument support for `--review-demo` and `--review-demo-scenario`.
   - Ensure review/demo mode does not require login, a companion app, or terminal setup.

4. Verify release assets and listing metadata.
   - Review `AppStore/AppStoreConnect.md`.
   - Review `AppStore/site/index.html` and `AppStore/site/privacy.html`.
   - Keep the independent-app disclaimer intact.

5. Keep screenshot generation working.
   - If UI changes affect marketing assets, rerun `scripts/generate_quotabar_screenshots.sh`.
   - Ensure the five screenshots still match the intended narrative and use QuotaBar branding only.

## Files To Modify First

- `Sources/QuotaBar/QuotaBarRateLimitClient.swift`
- `Sources/QuotaBar/QuotaBarReleaseGate.swift`
- `AppStore/QuotaBar.xcodeproj`
- `AppStore/Config/QuotaBar.entitlements`
- `AppStore/Resources/PrivacyInfo.xcprivacy`
- `AppStore/AppStoreConnect.md`

Modify shared `ToolbarCore` files only when needed to support the App Store client cleanly.

## Validation Checklist

- Build in Xcode with the `QuotaBar` scheme.
- Confirm the app launches in a clean environment with no external CLI installed.
- Confirm demo scenarios still work from both launch arguments and the menu.
- Confirm no App Store code path references `Process()`, PATH lookup, or shell execution.
- Confirm sandboxed behavior matches the final entitlement set.
- Confirm the support site, privacy policy, icon, and screenshots are consistent with QuotaBar branding.

## Archive And Submission

- Do not archive until `Sources/QuotaBar/QuotaBarReleaseGate.swift` is intentionally set to allow release.
- When the gate is open, archive with `scripts/archive_quotabar_app_store.sh`.
- Use Xcode Organizer or App Store Connect upload only after the archive succeeds and the review notes in `AppStore/AppStoreConnect.md` match the final behavior.

## Definition Of Done

The work is complete only when:

- QuotaBar has a real App-Store-safe live data source.
- Demo/review mode still works without external setup.
- The Xcode project has valid signing, versioning, entitlements, and privacy metadata.
- The archive script succeeds.
- App Store metadata, support pages, and screenshots all match the shipped behavior.
