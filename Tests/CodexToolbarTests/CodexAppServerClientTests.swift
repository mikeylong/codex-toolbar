import XCTest
@testable import CodexToolbar

final class CodexAppServerClientTests: XCTestCase {
    func testCodexPathCandidatesIncludeCommonFallbacks() {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/usr/bin:/bin",
            homeDirectory: "/Users/example"
        )

        XCTAssertEqual(
            candidates.prefix(4),
            [
                "/Applications/Codex.app/Contents/Resources/codex",
                "/Users/example/Applications/Codex.app/Contents/Resources/codex",
                "/usr/bin/codex",
                "/bin/codex"
            ]
        )
        XCTAssertTrue(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/example/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/example/.local/bin/codex"))
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/codex"))
    }

    func testCodexPathCandidatesDeduplicateEntries() {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/Applications/Codex.app/Contents/Resources:/opt/homebrew/bin:/Applications/Codex.app/Contents/Resources",
            homeDirectory: "/Users/example"
        )

        XCTAssertEqual(candidates.filter { $0 == "/Applications/Codex.app/Contents/Resources/codex" }.count, 1)
    }
}
