import XCTest
@testable import CodexToolbar

final class CodexAppServerClientTests: XCTestCase {
    func testCodexPathCandidatesIncludeCommonFallbacks() {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/usr/bin:/bin",
            homeDirectory: "/Users/example"
        )

        XCTAssertEqual(candidates.prefix(2), ["/usr/bin/codex", "/bin/codex"])
        XCTAssertTrue(candidates.contains("/Users/example/.local/bin/codex"))
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/codex"))
    }

    func testCodexPathCandidatesDeduplicateEntries() {
        let candidates = CodexAppServerClient.codexPathCandidates(
            environmentPath: "/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/bin",
            homeDirectory: "/Users/example"
        )

        XCTAssertEqual(candidates.filter { $0 == "/opt/homebrew/bin/codex" }.count, 1)
    }
}
