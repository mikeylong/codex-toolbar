import AppKit
import XCTest
@testable import CodexToolbar

@MainActor
final class AppDelegateTests: XCTestCase {
    func testPopoverContentShowsOpenCodexButtonWhenInstalledAppExists() {
        let delegate = makeDelegate(
            installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsOpenCodexButton)
    }

    func testPopoverContentHidesOpenCodexButtonWhenInstalledAppIsMissing() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertFalse(view.showsOpenCodexButton)
    }

    func testOpenCodexActionOpensAppAndClosesPopover() async {
        let fakeProvider = FakeCodexDesktopAppProvider(installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"))
        let delegate = makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: fakeProvider,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        let closeExpectation = expectation(description: "popover closed")
        delegate.popoverCloseHandler = {
            closeExpectation.fulfill()
        }

        let view = delegate.makeStatusMenuContentView()
        view.openCodexAction?()

        await fulfillment(of: [closeExpectation], timeout: 1)
        XCTAssertEqual(fakeProvider.openCallCount, 1)
    }

    func testScreenshotOverrideShowsOpenCodexButtonWithoutInstalledApp() {
        let screenshotConfiguration = ScreenshotLaunchConfiguration(
            scenario: .normal,
            appearance: .light,
            outputDirectory: nil,
            shouldCapturePopover: true,
            shouldCaptureStatusItem: false,
            shouldOpenPopover: true,
            visibleSupplementalFamilyIDs: nil,
            showsOpenCodexButton: true
        )
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            screenshotConfiguration: screenshotConfiguration
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsOpenCodexButton)
    }

    func testContextMenuIncludesSupplementalFamilyToggleAndDisabledVersionItemAboveQuit() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 7)
        XCTAssertEqual(menu.items[0].title, "Refresh now")
        XCTAssertTrue(
            menu.items[1].title == "Launch at login" ||
            menu.items[1].title == "Disable launch at login"
        )
        XCTAssertEqual(menu.items[2].title, "Show GPT-5.3-Codex-Spark")
        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.off)
        XCTAssertEqual(menu.items[3].title, "Show credits")
        XCTAssertEqual(menu.items[3].state, NSControl.StateValue.off)
        XCTAssertTrue(menu.items[4].isSeparatorItem)
        XCTAssertEqual(menu.items[5].title, "Version \(AppVersion.current)")
        XCTAssertFalse(menu.items[5].isEnabled)
        XCTAssertEqual(menu.items[6].title, "Quit")
    }

    func testContextMenuShowsUpdateItemsAboveVersionWhenUpdateIsAvailable() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let gitUpdateController = makeGitUpdateController(
            preferences: preferences,
            state: .updateAvailable("v0.1.4", .installFromGitCheckout)
        )
        let delegate = makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: preferences,
            gitUpdateController: gitUpdateController
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 9)
        XCTAssertEqual(menu.items[5].title, "Update available: v0.1.4")
        XCTAssertFalse(menu.items[5].isEnabled)
        XCTAssertEqual(menu.items[6].title, "Install update")
        XCTAssertTrue(menu.items[6].isEnabled)
        XCTAssertEqual(menu.items[7].title, "Version \(AppVersion.current)")
        XCTAssertEqual(menu.items[8].title, "Quit")
    }

    func testContextMenuShowsDownloadUpdateForReleaseBasedInstall() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let gitUpdateController = makeGitUpdateController(
            preferences: preferences,
            state: .updateAvailable(
                "v0.1.4",
                .downloadRelease(URL(string: "https://github.com/mikeylong/codex-toolbar/releases/latest")!)
            )
        )
        let delegate = makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: preferences,
            gitUpdateController: gitUpdateController
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[5].title, "Update available: v0.1.4")
        XCTAssertEqual(menu.items[6].title, "Download update")
    }

    func testContextMenuSupplementalFamilyToggleReflectsEnabledPreference() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "visibleSupplementalFamily.codex_bengalfox")
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.on)
    }

    func testContextMenuCreditsToggleReflectsEnabledPreference() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showCredits")
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[3].title, "Show credits")
        XCTAssertEqual(menu.items[3].state, NSControl.StateValue.on)
    }

    func testContextMenuCreditsToggleFlipsPreference() throws {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: preferences
        )
        let menu = delegate.makeContextMenu()
        let showCreditsItem = try XCTUnwrap(menu.items.first { $0.title == "Show credits" })
        let target = try XCTUnwrap(showCreditsItem.target as? NSObject)

        XCTAssertFalse(preferences.isCreditsVisible)

        target.perform(try XCTUnwrap(showCreditsItem.action))

        XCTAssertTrue(preferences.isCreditsVisible)
    }

    func testStatusMenuContentHidesSupplementalSectionsWhenPreferenceIsOff() {
        let defaults = Self.makeDefaults()
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertEqual(view.visibleSupplementalFamilyIDs, [])
        XCTAssertFalse(view.showsCredits)
    }

    func testStatusMenuContentShowsCreditsWhenPreferenceIsOn() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showCredits")
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsCredits)
    }

    func testStatusMenuContentShowsSupplementalSectionsWhenScreenshotOverrideIsEnabled() {
        let defaults = Self.makeDefaults()
        let screenshotConfiguration = ScreenshotLaunchConfiguration(
            scenario: .spark,
            appearance: .light,
            outputDirectory: nil,
            shouldCapturePopover: true,
            shouldCaptureStatusItem: false,
            shouldOpenPopover: true,
            visibleSupplementalFamilyIDs: ["codex_bengalfox"],
            showsOpenCodexButton: nil
        )
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults),
            screenshotConfiguration: screenshotConfiguration
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertEqual(view.visibleSupplementalFamilyIDs, ["codex_bengalfox"])
    }

    func testReadyStatusItemImageKeepsGlyphTintStableWhileBarColorChanges() throws {
        let palette = StatusMenuPalette.forAppearance(.light, colorScheme: .light)
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let warningImage = AppDelegate.readyStatusItemImage(
            bar: .init(remainingPercent: 18, progressState: .warning),
            appearance: appearance,
            glyphColor: palette.statusItemGlyphColor,
            trackColor: palette.trackColor(for: .warning),
            fillColor: palette.fillColor(for: .warning)
        )
        let criticalImage = AppDelegate.readyStatusItemImage(
            bar: .init(remainingPercent: 8, progressState: .critical),
            appearance: appearance,
            glyphColor: palette.statusItemGlyphColor,
            trackColor: palette.trackColor(for: .critical),
            fillColor: palette.fillColor(for: .critical)
        )

        let glyphRegion = NSRect(x: 0, y: 0, width: 16, height: 16)
        let barRegion = NSRect(x: 20, y: 0, width: 44, height: 16)

        XCTAssertEqual(try pixelData(for: warningImage, in: glyphRegion), try pixelData(for: criticalImage, in: glyphRegion))
        XCTAssertNotEqual(try pixelData(for: warningImage, in: barRegion), try pixelData(for: criticalImage, in: barRegion))
    }

    func testReadyStatusItemImageAppliesGlyphTintWithoutFlatteningTransparency() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let glyphColor = NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let image = AppDelegate.readyStatusItemImage(
            bar: .init(remainingPercent: 50, progressState: .normal),
            appearance: appearance,
            glyphColor: glyphColor,
            trackColor: NSColor(calibratedWhite: 0.2, alpha: 1.0),
            fillColor: NSColor(calibratedWhite: 0.6, alpha: 1.0)
        )
        let bitmap = try renderedBitmap(for: image)
        var transparentPixelCount = 0
        var tintedPixelCount = 0

        for y in 0..<16 {
            for x in 0..<16 {
                let color = try XCTUnwrap(
                    bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                )

                if color.alphaComponent < 0.05 {
                    transparentPixelCount += 1
                }

                if
                    color.alphaComponent > 0.2,
                    color.redComponent > 0.7,
                    color.greenComponent < 0.3,
                    color.blueComponent < 0.3
                {
                    tintedPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(transparentPixelCount, 0)
        XCTAssertGreaterThan(tintedPixelCount, 0)
    }

    func testUpdateStatusItemButtonSetsReadyTooltipWithoutChangingAccessibilityLabel() throws {
        let store = RateLimitStore(
            client: FakeStatusItemRateLimitClient(),
            initialState: .ready,
            initialCards: [
                RateLimitCardViewData(
                    window: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 50, windowDurationMins: 10_080),
                    familyId: "codex"
                )
            ],
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )
        let delegate = makeDelegate(
            store: store,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let button = try XCTUnwrap(statusItem.button)

        delegate.updateStatusItemButton(button)

        XCTAssertEqual(button.toolTip, "50% remaining")
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.accessibilityLabel(), "Codex toolbar. Weekly limit status open. 50% remaining.")
    }

    func testUpdateStatusItemButtonSetsErrorTooltipForTextPresentation() throws {
        let store = RateLimitStore(
            client: FakeStatusItemRateLimitClient(),
            initialState: .error("Codex CLI not found."),
            initialCards: [],
            initialStatusMessage: "Codex CLI not found.",
            liveUpdatesEnabled: false
        )
        let delegate = makeDelegate(
            store: store,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let button = try XCTUnwrap(statusItem.button)

        delegate.updateStatusItemButton(button)

        XCTAssertEqual(button.toolTip, "Codex CLI not found.")
        XCTAssertEqual(button.title, "!")
        XCTAssertEqual(button.accessibilityLabel(), "Codex toolbar. Codex CLI not found.")
    }

    func testHandleInstallUpdateResultTerminatesImmediatelyAfterDetachedUpdaterStarts() {
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            appRuntime: runtime
        )

        delegate.handleInstallUpdateResult(.started)

        XCTAssertEqual(runtime.terminateCallCount, 1)
        XCTAssertEqual(runtime.notifications.count, 0)
    }

    func testHandleInstallUpdateResultNotifiesOnPreflightFailureWithoutTerminating() {
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            appRuntime: runtime
        )

        delegate.handleInstallUpdateResult(.failed("Refusing to update from a dirty git worktree."))

        XCTAssertEqual(runtime.terminateCallCount, 0)
        XCTAssertEqual(runtime.notifications.count, 1)
        XCTAssertEqual(runtime.notifications[0].title, "CodexToolbar update failed")
        XCTAssertEqual(runtime.notifications[0].body, "Refusing to update from a dirty git worktree.")
    }

    func testHandleInstallUpdateResultOpensReleasePageWithoutTerminating() throws {
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            appRuntime: runtime
        )
        let releaseURL = try XCTUnwrap(URL(string: "https://github.com/mikeylong/codex-toolbar/releases/latest"))

        delegate.handleInstallUpdateResult(.openReleasePage(releaseURL))

        XCTAssertEqual(runtime.terminateCallCount, 0)
        XCTAssertEqual(runtime.openedURLs, [releaseURL])
        XCTAssertEqual(runtime.notifications.count, 0)
    }

    private func makeDelegate(
        installedApplicationURL: URL?,
        preferences: ToolbarPreferences,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil,
        appRuntime: any AppRuntimeControlling = FakeAppRuntimeController()
    ) -> AppDelegate {
        makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: installedApplicationURL),
            preferences: preferences,
            screenshotConfiguration: screenshotConfiguration,
            appRuntime: appRuntime
        )
    }

    private func makeDelegate(
        store: RateLimitStore,
        codexDesktopAppProvider: any CodexDesktopAppProviding,
        preferences: ToolbarPreferences,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil,
        gitUpdateController: GitUpdateController? = nil,
        appRuntime: any AppRuntimeControlling = FakeAppRuntimeController()
    ) -> AppDelegate {
        AppDelegate(
            store: store,
            loginItemController: LoginItemController(service: FakeLoginItemService()),
            gitUpdateController: gitUpdateController ?? makeGitUpdateController(preferences: preferences),
            codexDesktopAppProvider: codexDesktopAppProvider,
            preferences: preferences,
            maintenanceLaunchConfiguration: nil,
            screenshotConfiguration: screenshotConfiguration,
            startupDiagnosticsConfiguration: nil,
            appRuntime: appRuntime
        )
    }

    private func makeGitUpdateController(
        preferences: ToolbarPreferences,
        state: GitUpdateState = .upToDate
    ) -> GitUpdateController {
        let controller = GitUpdateController(
            service: GitUpdateService(tooling: FakeGitUpdateTooling()),
            preferences: preferences,
            refreshDelayNanosecondsProvider: { 1_000_000_000 }
        )
        controller.state = state
        return controller
    }

    private func makeSparkStore() -> RateLimitStore {
        RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "spark"],
            environment: [:]
        )
    }

    private func makeNormalStore() -> RateLimitStore {
        RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "normal"],
            environment: [:]
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "AppDelegateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func pixelData(for image: NSImage, in region: NSRect) throws -> Data {
        let bitmap = try renderedBitmap(for: image)

        var bytes: [UInt8] = []
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                bytes.append(UInt8((color.redComponent * 255).rounded()))
                bytes.append(UInt8((color.greenComponent * 255).rounded()))
                bytes.append(UInt8((color.blueComponent * 255).rounded()))
                bytes.append(UInt8((color.alphaComponent * 255).rounded()))
            }
        }

        return Data(bytes)
    }

    private func renderedBitmap(for image: NSImage) throws -> NSBitmapImageRep {
        let pixelsWide = Int(image.size.width)
        let pixelsHigh = Int(image.size.height)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }
}

@MainActor
private final class FakeCodexDesktopAppProvider: CodexDesktopAppProviding {
    let installedApplicationURL: URL?
    private(set) var openCallCount = 0

    init(installedApplicationURL: URL?) {
        self.installedApplicationURL = installedApplicationURL
    }

    func openCodex() async throws {
        openCallCount += 1
    }
}

@MainActor
private struct FakeLoginItemService: LoginItemService {
    var status: LoginItemRegistrationStatus { .notRegistered }

    func register() throws {}
    func unregister() throws {}
}

private final class FakeStatusItemRateLimitClient: @unchecked Sendable, CodexRateLimitClient {
    func events() -> AsyncStream<CodexAppServerEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func connect() async throws {}
    func disconnect() async {}

    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse {
        fatalError("Unused in AppDelegateTests")
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        fatalError("Unused in AppDelegateTests")
    }

    func readLoginStatus() async throws -> CodexLoginStatus {
        .loggedIn
    }

    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        fatalError("Unused in AppDelegateTests")
    }
}

private struct FakeGitUpdateTooling: GitUpdateTooling {
    func runGit(
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult {
        GitCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }

    func launchDetachedUpdate(configuration: GitUpdateRepositoryConfiguration) throws {}

    func fetchLatestReleaseTag(
        repositorySlug: String,
        timeoutNanoseconds: UInt64
    ) async throws -> String? {
        nil
    }
}

@MainActor
private final class FakeAppRuntimeController: AppRuntimeControlling {
    struct Notification: Equatable {
        let title: String
        let body: String
    }

    private(set) var terminateCallCount = 0
    private(set) var notifications: [Notification] = []
    private(set) var openedURLs: [URL] = []

    func terminate() {
        terminateCallCount += 1
    }

    func postNotification(title: String, body: String) {
        notifications.append(Notification(title: title, body: body))
    }

    func openURL(_ url: URL) throws {
        openedURLs.append(url)
    }
}
