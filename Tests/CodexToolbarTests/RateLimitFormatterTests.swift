import Foundation
import XCTest
@testable import CodexToolbar

final class RateLimitFormatterTests: XCTestCase {
    func testFiveHourWindowLabel() {
        XCTAssertEqual(RateLimitFormatter.windowLabel(for: 300), "5h")
    }

    func testWeeklyWindowLabel() {
        XCTAssertEqual(RateLimitFormatter.windowLabel(for: 10080), "Weekly")
    }

    func testRemainingPercentUsesInverseOfUsedPercent() {
        XCTAssertEqual(RateLimitFormatter.remainingPercent(fromUsedPercent: 15), 85)
        XCTAssertEqual(RateLimitFormatter.remainingPercent(fromUsedPercent: 9), 91)
    }

    func testSameDayResetUsesTimeFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let locale = Locale(identifier: "en_US_POSIX")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone

        let now = formatter.date(from: "2026-03-06T12:00:00Z")!
        let sameDay = formatter.date(from: "2026-03-06T13:54:00Z")!

        XCTAssertEqual(
            RateLimitFormatter.resetText(for: sameDay, now: now, calendar: calendar, locale: locale, timeZone: timeZone),
            "1:54 PM"
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
            RateLimitFormatter.resetText(for: futureDay, now: now, calendar: calendar, locale: locale, timeZone: timeZone),
            "Mar 11"
        )
    }
}
