import Foundation
import XCTest
@testable import CodexToolbar

final class RateLimitCardViewDataTests: XCTestCase {
    func testUsageCopyShowsUsedAndRemaining() {
        let card = RateLimitCardViewData(window: makeWindow(usedPercent: 16, durationMinutes: 10080))

        XCTAssertEqual(card.usageText, "16% used · 84% remaining")
    }

    func testProgressThresholds() {
        XCTAssertEqual(RateLimitCardViewData(window: makeWindow(usedPercent: 69, durationMinutes: 300)).progressState, .normal)
        XCTAssertEqual(RateLimitCardViewData(window: makeWindow(usedPercent: 70, durationMinutes: 300)).progressState, .warning)
        XCTAssertEqual(RateLimitCardViewData(window: makeWindow(usedPercent: 89, durationMinutes: 300)).progressState, .warning)
        XCTAssertEqual(RateLimitCardViewData(window: makeWindow(usedPercent: 90, durationMinutes: 300)).progressState, .critical)
        XCTAssertEqual(RateLimitCardViewData(window: makeWindow(usedPercent: 100, durationMinutes: 300)).progressState, .exhausted)
        XCTAssertEqual(RateLimitCardViewData(window: makeWindow(usedPercent: 30, durationMinutes: 300)).progressState, .normal)
    }

    func testExhaustedCardShowsReachedMessage() {
        let card = RateLimitCardViewData(window: makeWindow(usedPercent: 100, durationMinutes: 300))

        XCTAssertEqual(card.statusMessage, "Rate limit reached")
    }

    func testUsageCopyStillShowsUsedAndRemaining() {
        let card = RateLimitCardViewData(window: makeWindow(usedPercent: 90, durationMinutes: 300))

        XCTAssertEqual(card.usageText, "90% used · 10% remaining")
    }

    private func makeWindow(usedPercent: Int, durationMinutes: Int) -> CodexRateLimitWindow {
        CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: usedPercent, windowDurationMins: durationMinutes)
    }
}
