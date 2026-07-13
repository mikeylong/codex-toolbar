import XCTest
@testable import CodexToolbar

final class CodexAppServerClientTests: XCTestCase {
    func testSnapshotLoadTimeoutAllowsSlowTokenRefreshes() {
        XCTAssertGreaterThanOrEqual(CodexAppServerClient.snapshotLoadTimeoutSeconds, 15)
    }

    func testCodexPathCandidatesIncludeCommonFallbacks() {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/usr/bin:/bin",
            homeDirectory: "/Users/example"
        )

        XCTAssertEqual(
            candidates.prefix(6),
            [
                "/usr/bin/codex",
                "/bin/codex",
                "/Users/example/.local/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex"
            ]
        )
        XCTAssertTrue(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/example/Applications/ChatGPT.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/example/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/example/.local/bin/codex"))
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/codex"))
    }

    func testCodexPathCandidatesPreferInstalledCLIOverAppBundleExecutables() throws {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/Applications/ChatGPT.app/Contents/Resources:/opt/homebrew/bin",
            homeDirectory: "/Users/example"
        )

        XCTAssertLessThan(
            try XCTUnwrap(candidates.firstIndex(of: "/opt/homebrew/bin/codex")),
            try XCTUnwrap(candidates.firstIndex(of: "/Applications/ChatGPT.app/Contents/Resources/codex"))
        )
    }

    func testCodexPathCandidatesDeduplicateEntries() {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/Applications/ChatGPT.app/Contents/Resources:/opt/homebrew/bin:/Applications/ChatGPT.app/Contents/Resources",
            homeDirectory: "/Users/example"
        )

        XCTAssertEqual(candidates.filter { $0 == "/Applications/ChatGPT.app/Contents/Resources/codex" }.count, 1)
    }

    func testParseLoginStatusTreatsExitZeroAsLoggedIn() {
        let status = CodexAppServerClient.parseLoginStatus(
            exitStatus: 0,
            stdout: "Logged in using ChatGPT\n",
            stderr: "",
            timedOut: false
        )

        XCTAssertEqual(status, .loggedIn)
    }

    func testParseLoginStatusTreatsNotLoggedInAsLoggedOut() {
        let status = CodexAppServerClient.parseLoginStatus(
            exitStatus: 1,
            stdout: "Not logged in\n",
            stderr: "",
            timedOut: false
        )

        XCTAssertEqual(status, .loggedOut)
    }

    func testParseLoginStatusTreatsPermissionErrorsAsLoggedOut() {
        let status = CodexAppServerClient.parseLoginStatus(
            exitStatus: 1,
            stdout: "",
            stderr: "Error checking login status: Operation not permitted (os error 1)\n",
            timedOut: false
        )

        XCTAssertEqual(status, .loggedOut)
    }

    func testParseLoginStatusTreatsUnknownFailuresAsIndeterminate() {
        let status = CodexAppServerClient.parseLoginStatus(
            exitStatus: 2,
            stdout: "",
            stderr: "Unexpected login failure\n",
            timedOut: false
        )

        XCTAssertEqual(status, .indeterminate("Unexpected login failure"))
    }
}
