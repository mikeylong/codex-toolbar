import Foundation
import XCTest
@testable import CodexToolbar

final class RateLimitFormatterTests: XCTestCase {
    func testStatusBarWindowLabelUsesShortenedTokens() {
        XCTAssertEqual(RateLimitFormatter.statusBarWindowLabel(for: 10080), "Week")
        XCTAssertEqual(RateLimitFormatter.statusBarWindowLabel(for: 10081), "Week")
        XCTAssertEqual(RateLimitFormatter.statusBarWindowLabel(for: 20160), "2w")
        XCTAssertEqual(RateLimitFormatter.statusBarWindowLabel(for: 2880), "2d")
        XCTAssertEqual(RateLimitFormatter.statusBarWindowLabel(for: 300), "5h")
        XCTAssertEqual(RateLimitFormatter.statusBarWindowLabel(for: 45), "45m")
    }

    func testStatusBarStateLabelUsesApprovedUrgencyWords() {
        XCTAssertEqual(RateLimitFormatter.statusBarStateLabel(forRemainingPercent: 31), "Open")
        XCTAssertEqual(RateLimitFormatter.statusBarStateLabel(forRemainingPercent: 30), "Caution")
        XCTAssertEqual(RateLimitFormatter.statusBarStateLabel(forRemainingPercent: 10), "Tight")
        XCTAssertEqual(RateLimitFormatter.statusBarStateLabel(forRemainingPercent: 0), "Out")
    }

    func testStatusBarAccessibilityDescriptionUsesFullPhrase() {
        XCTAssertEqual(
            RateLimitFormatter.statusBarAccessibilityDescription(windowDurationMins: 10080, remainingPercent: 50),
            "Weekly limit status open. 50% remaining."
        )
    }

    func testFiveHourWindowLabel() {
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 300), "5h")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 300), "5h")
    }

    func testWeeklyWindowLabelUsesCanonicalAndOffByOneDuration() {
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 10080), "Weekly")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 10080), "Weekly")
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 10081), "Weekly")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 10081), "Weekly")
    }

    func testTwoWeekWindowLabelUsesCanonicalAndOffByOneDuration() {
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 20160), "2 Week")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 20160), "2 Week")
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 20161), "2 Week")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 20161), "2 Week")
    }

    func testDayWindowLabelUsesWordFallback() {
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 4320), "3 Day")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 4320), "3 Day")
    }

    func testNonNormalizedWindowFallsBackToMinuteLabel() {
        XCTAssertEqual(RateLimitFormatter.compactWindowLabel(for: 20162), "20162m")
        XCTAssertEqual(RateLimitFormatter.windowTitle(for: 20162), "20162m")
    }

    func testRemainingPercentUsesInverseOfUsedPercent() {
        XCTAssertEqual(RateLimitFormatter.remainingPercent(fromUsedPercent: 15), 85)
        XCTAssertEqual(RateLimitFormatter.remainingPercent(fromUsedPercent: 9), 91)
    }

    func testSameDayResetUsesRelativeAndAbsoluteFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let locale = Locale(identifier: "en_US_POSIX")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone

        let now = formatter.date(from: "2026-03-06T12:00:00Z")!
        let sameDay = formatter.date(from: "2026-03-06T13:12:00Z")!

        XCTAssertEqual(
            RateLimitFormatter.combinedResetText(for: sameDay, now: now, calendar: calendar, locale: locale, timeZone: timeZone),
            "Resets in 1h 12m (1:12 PM)"
        )
    }

    func testFutureDayResetUsesMonthDayFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let locale = Locale(identifier: "en_US_POSIX")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone

        let now = formatter.date(from: "2026-03-06T12:00:00Z")!
        let futureDay = formatter.date(from: "2026-03-11T12:00:00Z")!

        XCTAssertEqual(
            RateLimitFormatter.combinedResetText(for: futureDay, now: now, calendar: calendar, locale: locale, timeZone: timeZone),
            "Resets Mar 11"
        )
    }

    func testUpdatedFooterTextIncludesSeconds() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone

        let timestamp = formatter.date(from: "2026-03-06T13:03:07Z")!

        XCTAssertEqual(
            RateLimitFormatter.updatedFooterText(for: timestamp, locale: locale, timeZone: timeZone),
            "Updated 1:03:07 PM"
        )
    }
}
