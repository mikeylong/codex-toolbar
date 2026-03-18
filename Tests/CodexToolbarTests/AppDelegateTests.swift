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

        XCTAssertEqual(menu.items.count, 6)
        XCTAssertEqual(menu.items[0].title, "Refresh now")
        XCTAssertTrue(
            menu.items[1].title == "Launch at login" ||
            menu.items[1].title == "Disable launch at login"
        )
        XCTAssertEqual(menu.items[2].title, "Show GPT-5.3-Codex-Spark")
        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.off)
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, "Version \(AppVersion.current)")
        XCTAssertFalse(menu.items[4].isEnabled)
        XCTAssertEqual(menu.items[5].title, "Quit")
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

    func testStatusMenuContentHidesSupplementalSectionsWhenPreferenceIsOff() {
        let defaults = Self.makeDefaults()
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertEqual(view.visibleSupplementalFamilyIDs, [])
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

    private func makeDelegate(
        installedApplicationURL: URL?,
        preferences: ToolbarPreferences,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil
    ) -> AppDelegate {
        makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: installedApplicationURL),
            preferences: preferences,
            screenshotConfiguration: screenshotConfiguration
        )
    }

    private func makeDelegate(
        store: RateLimitStore,
        codexDesktopAppProvider: any CodexDesktopAppProviding,
        preferences: ToolbarPreferences,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil
    ) -> AppDelegate {
        AppDelegate(
            store: store,
            loginItemController: LoginItemController(service: FakeLoginItemService()),
            codexDesktopAppProvider: codexDesktopAppProvider,
            preferences: preferences,
            maintenanceLaunchConfiguration: nil,
            screenshotConfiguration: screenshotConfiguration,
            startupDiagnosticsConfiguration: nil
        )
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
