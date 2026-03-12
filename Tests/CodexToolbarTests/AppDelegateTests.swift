import AppKit
import XCTest
@testable import CodexToolbar

@MainActor
final class AppDelegateTests: XCTestCase {
    func testPopoverContentShowsOpenCodexButtonWhenInstalledAppExists() {
        let delegate = makeDelegate(installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"))

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsOpenCodexButton)
    }

    func testPopoverContentHidesOpenCodexButtonWhenInstalledAppIsMissing() {
        let delegate = makeDelegate(installedApplicationURL: nil)

        let view = delegate.makeStatusMenuContentView()

        XCTAssertFalse(view.showsOpenCodexButton)
    }

    func testOpenCodexActionOpensAppAndClosesPopover() async {
        let fakeProvider = FakeCodexDesktopAppProvider(installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"))
        let delegate = makeDelegate(codexDesktopAppProvider: fakeProvider)
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
            showsOpenCodexButton: true
        )
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            screenshotConfiguration: screenshotConfiguration
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsOpenCodexButton)
    }

    func testContextMenuIncludesDisabledVersionItemAboveQuit() {
        let delegate = AppDelegate()

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 5)
        XCTAssertEqual(menu.items[0].title, "Refresh now")
        XCTAssertTrue(
            menu.items[1].title == "Launch at login" ||
            menu.items[1].title == "Disable launch at login"
        )
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Version \(AppVersion.current)")
        XCTAssertFalse(menu.items[3].isEnabled)
        XCTAssertEqual(menu.items[4].title, "Quit")
    }

    private func makeDelegate(
        installedApplicationURL: URL?,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil
    ) -> AppDelegate {
        makeDelegate(
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: installedApplicationURL),
            screenshotConfiguration: screenshotConfiguration
        )
    }

    private func makeDelegate(
        codexDesktopAppProvider: any CodexDesktopAppProviding,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil
    ) -> AppDelegate {
        AppDelegate(
            store: RateLimitStore.makeShared(
                arguments: ["CodexToolbar", "--screenshot-scenario", "normal"],
                environment: [:]
            ),
            loginItemController: LoginItemController(service: FakeLoginItemService()),
            codexDesktopAppProvider: codexDesktopAppProvider,
            maintenanceLaunchConfiguration: nil,
            screenshotConfiguration: screenshotConfiguration,
            startupDiagnosticsConfiguration: nil
        )
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
