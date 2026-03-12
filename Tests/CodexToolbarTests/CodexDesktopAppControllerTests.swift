import AppKit
import XCTest
@testable import CodexToolbar

@MainActor
final class CodexDesktopAppControllerTests: XCTestCase {
    func testAppBundleCandidatesIncludeSystemAndUserApplications() {
        let candidates = CodexDesktopAppLocator.appBundleCandidates(homeDirectory: "/Users/example")

        XCTAssertEqual(candidates, [
            "/Applications/Codex.app",
            "/Users/example/Applications/Codex.app"
        ])
    }

    func testInstalledApplicationURLPrefersFirstExistingCandidate() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let systemAppURL = tempDirectory.appendingPathComponent("Applications/Codex.app", isDirectory: true)
        let userAppURL = tempDirectory.appendingPathComponent("Users/example/Applications/Codex.app", isDirectory: true)

        try FileManager.default.createDirectory(at: systemAppURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userAppURL, withIntermediateDirectories: true)

        let locator = CodexDesktopAppLocator(
            fileManager: .default,
            bundleCandidates: [systemAppURL.path, userAppURL.path]
        )

        XCTAssertEqual(locator.installedApplicationURL()?.path, systemAppURL.path)
    }

    func testInstalledApplicationURLFallsBackToUserApplication() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let systemAppURL = tempDirectory.appendingPathComponent("Applications/Codex.app", isDirectory: true)
        let userAppURL = tempDirectory.appendingPathComponent("Users/example/Applications/Codex.app", isDirectory: true)

        try FileManager.default.createDirectory(at: userAppURL, withIntermediateDirectories: true)

        let locator = CodexDesktopAppLocator(
            fileManager: .default,
            bundleCandidates: [systemAppURL.path, userAppURL.path]
        )

        XCTAssertEqual(locator.installedApplicationURL()?.path, userAppURL.path)
    }

    func testInstalledApplicationURLReturnsNilWhenNoBundleExists() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = CodexDesktopAppLocator(
            fileManager: .default,
            bundleCandidates: [
                tempDirectory.appendingPathComponent("Applications/Codex.app", isDirectory: true).path,
                tempDirectory.appendingPathComponent("Users/example/Applications/Codex.app", isDirectory: true).path
            ]
        )

        XCTAssertNil(locator.installedApplicationURL())
    }

    func testOpenCodexUsesWorkspaceActivation() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let appURL = tempDirectory.appendingPathComponent("Applications/Codex.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let workspace = FakeWorkspaceApplicationOpener()
        let controller = CodexDesktopAppController(
            locator: CodexDesktopAppLocator(
                fileManager: .default,
                bundleCandidates: [appURL.path]
            ),
            workspace: workspace
        )

        try await controller.openCodex()

        XCTAssertEqual(workspace.openedApplicationURL?.path, appURL.path)
        XCTAssertEqual(workspace.lastConfiguration?.activates, true)
        XCTAssertEqual(workspace.lastConfiguration?.createsNewApplicationInstance, false)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

@MainActor
private final class FakeWorkspaceApplicationOpener: WorkspaceApplicationOpening {
    private(set) var openedApplicationURL: URL?
    private(set) var lastConfiguration: NSWorkspace.OpenConfiguration?

    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws {
        openedApplicationURL = url
        lastConfiguration = configuration
    }
}
