import XCTest
@testable import CodexToolbar

final class ClaudeUsagePanelPresentationTests: XCTestCase {
    func testCoreAndModelLimitsHaveSeparateGroupsWithoutInventingWindows() {
        let presentation = ClaudeUsagePanelPresentation(windows: [
            window("Weekly (Fable)", used: 100),
            window("Session", used: 2),
            window("Weekly", used: 63)
        ])

        XCTAssertEqual(presentation.coreWindows.map(\.title), ["Session", "Weekly"])
        XCTAssertEqual(presentation.modelWindows.map(\.title), ["Weekly (Fable)"])
        XCTAssertEqual(presentation.coreWindows.map(\.remainingPercent), [98, 37])
        XCTAssertEqual(presentation.modelWindows.first?.remainingPercent, 0)

        let modelOnly = ClaudeUsagePanelPresentation(windows: [window("Weekly (Fable)", used: 100)])
        XCTAssertTrue(modelOnly.coreWindows.isEmpty)
        XCTAssertEqual(modelOnly.modelWindows.count, 1)
    }

    func testLocalTimeZoneSuffixIsRemovedOnlyWhenExactlyMatched() {
        let reset = "Resets Nov 16 at 7:59pm (America/Los_Angeles)"
        XCTAssertEqual(
            ClaudeUsagePanelPresentation.compactResetDescription(reset, localTimeZoneIdentifier: "America/Los_Angeles"),
            "Resets Nov 16 at 7:59pm"
        )
        XCTAssertEqual(
            ClaudeUsagePanelPresentation.compactResetDescription(reset, localTimeZoneIdentifier: "America/New_York"),
            reset
        )
        XCTAssertEqual(
            ClaudeUsagePanelPresentation.compactResetDescription("Resets in 2 hours", localTimeZoneIdentifier: "America/Los_Angeles"),
            "Resets in 2 hours"
        )
        XCTAssertNil(ClaudeUsagePanelPresentation.compactResetDescription(nil))
    }

    func testCompactingPresentationDoesNotChangeAccessibleSourceDescription() {
        let reset = "Resets Nov 16 at 7:59pm (America/Los_Angeles)"
        let data = ClaudeUsageWindowViewData(window: ClaudeUsageWindow(
            id: "session", title: "Session", usedPercent: 2, resetDescription: reset
        ))

        _ = ClaudeUsagePanelPresentation.compactResetDescription(data.resetDescription, localTimeZoneIdentifier: "America/Los_Angeles")

        XCTAssertEqual(data.resetDescription, reset)
        XCTAssertTrue(data.accessibilityLabel.contains(reset))
        XCTAssertTrue(data.accessibilityLabel.contains("2% used"))
        XCTAssertTrue(data.accessibilityLabel.contains("98% remaining"))
    }

    private func window(_ title: String, used: Int) -> ClaudeUsageWindowViewData {
        ClaudeUsageWindowViewData(window: ClaudeUsageWindow(
            id: title, title: title, usedPercent: used, resetDescription: nil
        ))
    }
}
