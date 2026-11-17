import XCTest
@testable import CodexToolbar

final class ClaudeUsageWindowViewDataTests: XCTestCase {
    func testCoreWindowClassificationKeepsModelSpecificLimitsSeparate() {
        for title in ["Session", "Current session", "Weekly", "Current week", "Weekly (all models)", "Current week (all models)"] {
            let data = ClaudeUsageWindowViewData(window: ClaudeUsageWindow(
                id: title, title: title, usedPercent: 10, resetDescription: nil
            ))
            XCTAssertTrue(data.isCoreWindow, title)
        }
        for title in ["Weekly (Fable)", "Weekly (Sonnet)", "Unknown limit"] {
            let data = ClaudeUsageWindowViewData(window: ClaudeUsageWindow(
                id: title, title: title, usedPercent: 100, resetDescription: nil
            ))
            XCTAssertFalse(data.isCoreWindow, title)
        }
    }

    func testDisplaysRemainingPercentageAndPreservesCLIResetDescription() {
        let reset = "Resets Nov 16 at 3pm (America/Los_Angeles)"
        let data = ClaudeUsageWindowViewData(window: ClaudeUsageWindow(
            id: "session", title: "Current session", usedPercent: 28, resetDescription: reset
        ))

        XCTAssertEqual(data.remainingPercent, 72)
        XCTAssertEqual(data.usageText, "28% used · 72% remaining")
        XCTAssertEqual(data.resetDescription, reset)
        XCTAssertEqual(data.accessibilityLabel, "Claude Current session. 28% used. 72% remaining. \(reset)")
    }

    func testMissingResetDoesNotInventTiming() {
        let data = ClaudeUsageWindowViewData(window: ClaudeUsageWindow(
            id: "weekly", title: "Current week", usedPercent: 100, resetDescription: nil
        ))

        XCTAssertNil(data.resetDescription)
        XCTAssertEqual(data.remainingPercent, 0)
        XCTAssertEqual(data.accessibilityLabel, "Claude Current week. 100% used. 0% remaining")
    }
}
