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

    func testDisplayLabelOverrideDrivesTitleAndCompactLabel() {
        let card = RateLimitCardViewData(
            window: makeWindow(usedPercent: 16, durationMinutes: 20160),
            displayLabelOverride: "Weekly"
        )

        XCTAssertEqual(card.title, "Weekly")
        XCTAssertEqual(card.compactLabel, "Weekly")
    }

    func testPopoverTitleDropsCategoryPrefixWhenGroupedByFamily() {
        let card = RateLimitCardViewData(
            window: makeWindow(usedPercent: 16, durationMinutes: 300),
            familyId: "codex_bengalfox",
            categoryLabel: "GPT-5.3-Codex-Spark"
        )

        XCTAssertEqual(card.popoverTitle(isGroupedByFamily: false), "GPT-5.3-Codex-Spark · 5h")
        XCTAssertEqual(card.popoverTitle(isGroupedByFamily: true), "5h")
    }

    func testWeeklyProjectionShowsResetFirstWhenProjectedEmptyFallsAfterReset() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        let card = makeWeeklyCard(usedPercent: 25, reset: reset, now: now)
        let projection = try XCTUnwrap(card.projection)

        XCTAssertEqual(projection.state, .resetFirst)
        XCTAssertEqual(projection.summaryText, "Reset comes first")
        XCTAssertEqual(projection.detailText, "On pace to last through reset")
        XCTAssertEqual(projection.dailyUsePercent, 12.5, accuracy: 0.001)
        XCTAssertEqual(projection.projectedEmptyDate.timeIntervalSince1970, makeDate(year: 2026, month: 5, day: 19, hour: 12, minute: 0).timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(projection.currentPosition, 0.25, accuracy: 0.001)
        XCTAssertEqual(projection.resetPosition, 0.875, accuracy: 0.001)
        XCTAssertEqual(projection.projectedEmptyPosition, 1.0, accuracy: 0.001)
        XCTAssertEqual(projection.paceTooltipText, "Current pace · 12.5% used per day")
        XCTAssertEqual(projection.currentTooltipText, "Now · 75% remaining")
        XCTAssertEqual(projection.resetTooltipText, "Reset · May 18")
        XCTAssertEqual(projection.projectedEmptyTooltipText, "Projected empty · May 19 at current pace")
        XCTAssertEqual(projection.tooltipText(for: .pace), projection.paceTooltipText)
        XCTAssertEqual(projection.tooltipText(for: .current), projection.currentTooltipText)
        XCTAssertEqual(projection.tooltipText(for: .reset), projection.resetTooltipText)
        XCTAssertEqual(projection.tooltipText(for: .projectedEmpty), projection.projectedEmptyTooltipText)
        XCTAssertTrue(card.accessibilityLabel.contains("Reset comes first"))
        XCTAssertTrue(card.accessibilityLabel.contains("On pace to last through reset"))
        XCTAssertTrue(card.accessibilityLabel.contains(projection.paceTooltipText))
        XCTAssertTrue(projection.accessibilityLabel.contains("Weekly pace"))
    }

    func testFiveHourProjectionShowsResetFirstWhenProjectedEmptyFallsAfterReset() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 13, hour: 16, minute: 0)
        let card = makeFiveHourCard(usedPercent: 10, reset: reset, now: now)
        let projection = try XCTUnwrap(card.projection)

        XCTAssertEqual(projection.state, .resetFirst)
        XCTAssertEqual(projection.summaryText, "Reset comes first")
        XCTAssertEqual(projection.detailText, "On pace to last through reset")
        XCTAssertEqual(projection.dailyUsePercent, 240, accuracy: 0.001)
        XCTAssertEqual(projection.projectedEmptyDate.timeIntervalSince1970, makeDate(year: 2026, month: 5, day: 13, hour: 21, minute: 0).timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(projection.currentPosition, 0.1, accuracy: 0.001)
        XCTAssertEqual(projection.resetPosition, 0.5, accuracy: 0.001)
        XCTAssertEqual(projection.projectedEmptyPosition, 1.0, accuracy: 0.001)
        XCTAssertEqual(projection.paceTooltipText, "Current pace · 10% used per hour")
        XCTAssertEqual(projection.currentTooltipText, "Now · 90% remaining")
        XCTAssertEqual(projection.resetTooltipText, "Reset · 4:00 PM")
        XCTAssertEqual(projection.projectedEmptyTooltipText, "Projected empty · 9:00 PM at current pace")
        XCTAssertTrue(projection.accessibilityLabel.contains("5h pace"))
    }

    func testProjectionGraphLayoutTargetsMarkersResetAndPaceWithoutTargetingBaseline() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        let projection = try XCTUnwrap(makeWeeklyCard(usedPercent: 25, reset: reset, now: now).projection)
        let layout = RateLimitProjectionGraphLayout(
            size: CGSize(width: 320, height: 31),
            projection: projection
        )

        XCTAssertEqual(layout.hoverTarget(at: layout.currentPoint)?.element, .current)
        XCTAssertEqual(
            layout.hoverTarget(at: CGPoint(x: layout.currentPoint.x + 8, y: layout.currentPoint.y))?.element,
            .current
        )
        let emptyTarget = try XCTUnwrap(layout.hoverTarget(at: layout.emptyPoint))
        XCTAssertEqual(emptyTarget.element, .projectedEmpty)
        XCTAssertEqual(layout.tooltipPosition(for: emptyTarget).x, 202, accuracy: 0.001)
        XCTAssertEqual(
            layout.hoverTarget(at: CGPoint(x: layout.resetX, y: layout.topY))?.element,
            .reset
        )

        let pacePoint = CGPoint(
            x: (layout.startPoint.x + layout.currentPoint.x) / 2,
            y: (layout.startPoint.y + layout.currentPoint.y) / 2
        )
        XCTAssertEqual(layout.hoverTarget(at: pacePoint)?.element, .pace)

        let baselinePoint = CGPoint(x: layout.horizontalInset + 20, y: layout.bottomY)
        XCTAssertNil(layout.hoverTarget(at: baselinePoint))
    }

    func testFiveHourProjectionIsCriticalWhenProjectedEmptyFallsBeforeReset() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 13, hour: 16, minute: 0)
        let card = makeFiveHourCard(usedPercent: 50, reset: reset, now: now)
        let projection = try XCTUnwrap(card.projection)

        XCTAssertEqual(projection.state, .critical)
        XCTAssertEqual(projection.summaryText, "Projected empty before reset")
        XCTAssertEqual(projection.detailText, "Empty 1:00 PM at pace")
        XCTAssertEqual(projection.projectedEmptyDate.timeIntervalSince1970, makeDate(year: 2026, month: 5, day: 13, hour: 13, minute: 0).timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(projection.currentPosition, 0.2, accuracy: 0.001)
        XCTAssertEqual(projection.resetPosition, 1.0, accuracy: 0.001)
        XCTAssertEqual(projection.projectedEmptyPosition, 0.4, accuracy: 0.001)
    }

    func testWeeklyProjectionWarnsWhenProjectedEmptyFallsBeforeReset() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        let card = makeWeeklyCard(usedPercent: 50, reset: reset, now: now)
        let projection = try XCTUnwrap(card.projection)

        XCTAssertEqual(projection.state, .warning)
        XCTAssertEqual(projection.summaryText, "Projected empty before reset")
        XCTAssertEqual(projection.detailText, "Empty May 15 at pace")
        XCTAssertEqual(projection.projectedEmptyDate.timeIntervalSince1970, makeDate(year: 2026, month: 5, day: 15, hour: 12, minute: 0).timeIntervalSince1970, accuracy: 0.5)
    }

    func testWeeklyProjectionIsCriticalWhenProjectedEmptyFallsWithinADay() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        let card = makeWeeklyCard(usedPercent: 80, reset: reset, now: now)
        let projection = try XCTUnwrap(card.projection)

        XCTAssertEqual(projection.state, .critical)
        XCTAssertEqual(projection.summaryText, "Projected empty before reset")
        XCTAssertEqual(projection.projectedEmptyDate.timeIntervalSince1970, makeDate(year: 2026, month: 5, day: 14, hour: 0, minute: 0).timeIntervalSince1970, accuracy: 0.5)
    }

    func testWeeklyProjectionHandlesExhaustedWindow() throws {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let reset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        let card = makeWeeklyCard(usedPercent: 100, reset: reset, now: now)
        let projection = try XCTUnwrap(card.projection)

        XCTAssertEqual(card.progressState, .exhausted)
        XCTAssertEqual(projection.state, .critical)
        XCTAssertEqual(projection.currentRemainingPercent, 0)
        XCTAssertEqual(projection.projectedEmptyDate, now)

        let layout = RateLimitProjectionGraphLayout(
            size: CGSize(width: 320, height: 31),
            projection: projection
        )
        let target = try XCTUnwrap(layout.hoverTarget(at: layout.currentPoint))
        XCTAssertEqual(target.element, .currentAndProjectedEmpty)
        XCTAssertEqual(projection.tooltipText(for: target.element), "Now · 0% remaining · projected empty")
    }

    func testProjectionIsHiddenWhenInputsAreUnavailable() {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let fiveHourReset = makeDate(year: 2026, month: 5, day: 13, hour: 16, minute: 0)
        let weeklyReset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)

        XCTAssertNil(makeFiveHourCard(usedPercent: 0, reset: fiveHourReset, now: now).projection)
        XCTAssertNil(makeFiveHourCard(usedPercent: 25, reset: nil, now: now).projection)
        XCTAssertNil(makeCard(usedPercent: 25, reset: fiveHourReset, durationMinutes: nil, now: now).projection)
        XCTAssertNil(makeFiveHourCard(usedPercent: 25, reset: fiveHourReset, now: makeDate(year: 2026, month: 5, day: 13, hour: 10, minute: 30)).projection)
        XCTAssertNil(makeWeeklyCard(usedPercent: 0, reset: weeklyReset, now: now).projection)
        XCTAssertNil(makeWeeklyCard(usedPercent: 25, reset: weeklyReset, now: makeDate(year: 2026, month: 5, day: 10, hour: 12, minute: 0)).projection)
    }

    func testProjectionOnlyAppearsForCoreCodexFiveHourAndWeeklyWindows() {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let fiveHourReset = makeDate(year: 2026, month: 5, day: 13, hour: 16, minute: 0)
        let weeklyReset = makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        let coreFiveHourCard = makeFiveHourCard(usedPercent: 25, reset: fiveHourReset, now: now)
        let coreWeeklyCard = makeWeeklyCard(usedPercent: 25, reset: weeklyReset, now: now)
        let coreTwoWeekCard = makeCard(usedPercent: 25, reset: weeklyReset, durationMinutes: 20_160, now: now)
        let supplementalFiveHourCard = RateLimitCardViewData(
            window: makeWindow(usedPercent: 25, reset: fiveHourReset, durationMinutes: 300),
            familyId: "codex_bengalfox",
            categoryLabel: "GPT-5.3-Codex-Spark",
            now: now,
            calendar: testCalendar,
            locale: testLocale,
            timeZone: testTimeZone
        )
        let supplementalWeeklyCard = RateLimitCardViewData(
            window: makeWindow(usedPercent: 25, reset: weeklyReset, durationMinutes: 10_080),
            familyId: "codex_bengalfox",
            categoryLabel: "GPT-5.3-Codex-Spark",
            now: now,
            calendar: testCalendar,
            locale: testLocale,
            timeZone: testTimeZone
        )

        XCTAssertNotNil(coreFiveHourCard.projection)
        XCTAssertNotNil(coreWeeklyCard.projection)
        XCTAssertNil(coreTwoWeekCard.projection)
        XCTAssertNil(supplementalFiveHourCard.projection)
        XCTAssertNil(supplementalWeeklyCard.projection)
    }

    private func makeWindow(usedPercent: Int, durationMinutes: Int) -> CodexRateLimitWindow {
        CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: usedPercent, windowDurationMins: durationMinutes)
    }

    private func makeWindow(usedPercent: Int, reset: Date?, durationMinutes: Int?) -> CodexRateLimitWindow {
        CodexRateLimitWindow(
            resetsAt: reset.map { Int64($0.timeIntervalSince1970) },
            usedPercent: usedPercent,
            windowDurationMins: durationMinutes
        )
    }

    private func makeWeeklyCard(usedPercent: Int, reset: Date?, now: Date) -> RateLimitCardViewData {
        makeCard(usedPercent: usedPercent, reset: reset, durationMinutes: 10_080, now: now)
    }

    private func makeFiveHourCard(usedPercent: Int, reset: Date?, now: Date) -> RateLimitCardViewData {
        makeCard(usedPercent: usedPercent, reset: reset, durationMinutes: 300, now: now)
    }

    private func makeCard(
        usedPercent: Int,
        reset: Date?,
        durationMinutes: Int?,
        now: Date
    ) -> RateLimitCardViewData {
        RateLimitCardViewData(
            window: makeWindow(usedPercent: usedPercent, reset: reset, durationMinutes: durationMinutes),
            now: now,
            calendar: testCalendar,
            locale: testLocale,
            timeZone: testTimeZone
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        return calendar
    }

    private var testLocale: Locale {
        Locale(identifier: "en_US_POSIX")
    }

    private var testTimeZone: TimeZone {
        TimeZone(identifier: "America/Los_Angeles")!
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        testCalendar.date(from: DateComponents(
            timeZone: testTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
