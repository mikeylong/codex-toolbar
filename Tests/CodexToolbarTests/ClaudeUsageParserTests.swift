import XCTest
@testable import CodexToolbar

final class ClaudeUsageParserTests: XCTestCase {
    func testReadsOnlyQuotaWindowsAndPreservesResetDescriptions() throws {
        let snapshot = try ClaudeUsageParser.parse(envelope("""
        You are currently using your subscription to power your Claude Code usage

        Current session: 100% used · resets Nov 16 at 3pm (America/Los_Angeles)
        Current week (all models): 63% used · resets Nov 17 at 1pm (America/Los_Angeles)
        Current week (Fable): 100% used · resets Nov 17 at 1pm (America/Los_Angeles)

        What’s contributing to your usage?
        Tool calls: 80%
        Current week (Misleading project title): 99% used · resets tomorrow
        """))
        XCTAssertEqual(snapshot.windows, [
            .init(id: "current-session", title: "Session", usedPercent: 100,
                  resetDescription: "Resets Nov 16 at 3pm (America/Los_Angeles)"),
            .init(id: "current-week-all-models", title: "Weekly", usedPercent: 63,
                  resetDescription: "Resets Nov 17 at 1pm (America/Los_Angeles)"),
            .init(id: "current-week-fable", title: "Weekly (Fable)", usedPercent: 100,
                  resetDescription: "Resets Nov 17 at 1pm (America/Los_Angeles)")
        ])
    }

    func testWeeklyOnlyAndMissingResetAreValid() throws {
        let snapshot = try ClaudeUsageParser.parse(envelope("Current week (all models): 0% used"))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent, 0)
        XCTAssertNil(snapshot.windows[0].resetDescription)
    }

    func testConvertsRemainingAndNormalizesResetPrefixOnce() throws {
        let snapshot = try ClaudeUsageParser.parse(envelope("Current session: 74% left · Reset in 2 hours"))
        XCTAssertEqual(snapshot.windows[0].usedPercent, 26)
        XCTAssertEqual(snapshot.windows[0].resetDescription, "Resets in 2 hours")
    }

    func testCostOnlyAndInsightsOnlyAreNotQuotaMeasurements() throws {
        for report in ["Total cost: $0.0000\nUsage: 0 input, 0 output", "What's contributing to your usage?\nCurrent session: 80% used"] {
            XCTAssertThrowsError(try ClaudeUsageParser.parse(envelope(report))) {
                XCTAssertEqual($0 as? ClaudeUsageError, .noQuotaData)
            }
        }
    }

    func testRejectsInvalidPercentagesAndDuplicateWindows() throws {
        for report in ["Current session: 101% used", "Current session: -1% used", "Current session: NaN% used",
                       "Current session: 10% used\nCurrent session: 20% used", "Current session: unavailable"] {
            XCTAssertThrowsError(try ClaudeUsageParser.parse(envelope(report))) {
                XCTAssertEqual($0 as? ClaudeUsageError, .unsupportedResponse)
            }
        }
    }

    func testRequiresLocalUsageCommandWithoutModelWork() throws {
        for override in [["num_turns": 1], ["duration_api_ms": 1], ["total_cost_usd": 0.01],
                         ["local_command": "status"], ["type": "assistant"], ["subtype": "error_max_budget_usd"]] as [[String: Any]] {
            XCTAssertThrowsError(try ClaudeUsageParser.parse(envelope("Current session: 10% used", overriding: override))) {
                XCTAssertEqual($0 as? ClaudeUsageError, .unsupportedResponse)
            }
        }
        XCTAssertThrowsError(try ClaudeUsageParser.parse(Data("Current session: 10% used".utf8)))
    }

    func testExplicitAuthenticationFailureDiffersFromNetworkFailure() throws {
        XCTAssertThrowsError(try ClaudeUsageParser.parse(envelope("Not logged in. Please run /login", overriding: ["is_error": true]))) {
            XCTAssertEqual($0 as? ClaudeUsageError, .notAuthenticated)
        }
        XCTAssertThrowsError(try ClaudeUsageParser.parse(envelope("Network connection failed", overriding: ["is_error": true]))) {
            XCTAssertEqual($0 as? ClaudeUsageError, .commandFailed)
        }
        XCTAssertFalse(ClaudeUsageParser.reportsAuthenticationFailure("Keychain access denied"))
    }

    private func envelope(_ report: String, overriding overrides: [String: Any] = [:]) -> Data {
        var fields: [String: Any] = ["type": "result", "local_command": "usage", "subtype": "success",
                                   "is_error": false, "num_turns": 0, "duration_api_ms": 0,
                                   "total_cost_usd": 0, "result": report]
        fields.merge(overrides) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: fields)
    }
}
