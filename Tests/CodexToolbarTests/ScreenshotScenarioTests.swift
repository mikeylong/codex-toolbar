import Foundation
import XCTest
@testable import CodexToolbar

@MainActor
final class ScreenshotScenarioTests: XCTestCase {
    func testWarningScenarioMapsToExpectedCardStates() throws {
        let scenario = try XCTUnwrap(ScreenshotScenario.named("warning"))

        let cards = RateLimitStore.makeCards(
            from: scenario.snapshot,
            now: scenario.now,
            calendar: scenario.calendar,
            locale: scenario.locale,
            timeZone: scenario.timeZone
        )

        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].title, "5h")
        XCTAssertEqual(cards[0].progressState, .warning)
        XCTAssertEqual(cards[0].usageText, "74% used · 26% remaining")
        XCTAssertEqual(cards[0].combinedResetText, "Resets in 35m (2:46 PM)")
        XCTAssertEqual(cards[1].progressState, .normal)
    }

    func testScreenshotModeBuildsFixtureStoreWithoutLiveFetching() async {
        let client = FakeScreenshotClient()
        let store = RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "normal"],
            environment: [:],
            clientFactory: { client }
        )

        await store.start()

        XCTAssertEqual(client.loadSnapshotCallCount, 0)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.cards.first?.usageText, "19% used · 81% remaining")
        XCTAssertEqual(store.statusBarText, "5h: Open")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 81, progressState: .normal))
        )
        XCTAssertEqual(store.lastUpdated, ScreenshotScenario.normal.lastUpdated)
    }

    func testMultiWeekScenarioBuildsWeeklyCoreCodexLabelsEndToEnd() async {
        let client = FakeScreenshotClient()
        let store = RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "multiweek"],
            environment: [:],
            clientFactory: { client }
        )

        await store.start()

        XCTAssertEqual(client.loadSnapshotCallCount, 0)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.cards.first?.compactLabel, "Weekly")
        XCTAssertEqual(store.cards.first?.title, "Weekly")
        XCTAssertEqual(store.statusBarText, "Week: Tight")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 1, progressState: .critical))
        )
        XCTAssertEqual(store.lastUpdated, ScreenshotScenario.multiweek.lastUpdated)
    }

    func testProjectionScenarioBuildsWeeklyResetRiskChartData() throws {
        let scenario = try XCTUnwrap(ScreenshotScenario.named("projection"))
        let cards = RateLimitStore.makeCards(
            from: scenario.snapshot,
            now: scenario.now,
            calendar: scenario.calendar,
            locale: scenario.locale,
            timeZone: scenario.timeZone
        )
        let weeklyCard = try XCTUnwrap(cards.first { $0.title == "Weekly" })
        let projection = try XCTUnwrap(weeklyCard.projection)

        XCTAssertEqual(projection.state, .resetFirst)
        XCTAssertEqual(projection.summaryText, "Reset comes first")
        XCTAssertEqual(projection.detailText, "On pace to last through reset")
    }

    func testSparkScenarioBuildsFamilySectionsWithCodexFirst() throws {
        let scenario = try XCTUnwrap(ScreenshotScenario.named("spark"))
        let cards = RateLimitStore.makeCards(
            from: scenario.rateLimitsResponse,
            now: scenario.now,
            calendar: scenario.calendar,
            locale: scenario.locale,
            timeZone: scenario.timeZone
        )
        let sections = RateLimitStore.makeCardSections(from: cards)

        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(cards.first?.displayTitle, "GPT-5.3-Codex-Spark · 5h")
        XCTAssertEqual(sections.map(\.familyId), ["codex", "codex_bengalfox"])
        XCTAssertEqual(sections.map(\.title), [nil, "GPT-5.3-Codex-Spark limit"])
        XCTAssertEqual(sections.map(\.showsTitle), [false, true])
        XCTAssertEqual(sections[0].cards.map(\.title), ["5h", "Weekly"])
        XCTAssertEqual(sections[1].cards.map(\.title), ["5h", "2 Week"])
    }

    func testSparkScenarioBuildsStoreFromLaunchWithoutLiveFetching() async {
        let client = FakeScreenshotClient()
        let store = RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "spark"],
            environment: [:],
            clientFactory: { client }
        )

        await store.start()

        XCTAssertEqual(client.loadSnapshotCallCount, 0)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.cardSections.map(\.title), [nil, "GPT-5.3-Codex-Spark limit"])
        XCTAssertEqual(store.statusBarText, "Week: Open")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 50, progressState: .normal))
        )
        XCTAssertEqual(store.lastUpdated, ScreenshotScenario.spark.lastUpdated)
    }

    func testSparkScenarioCanHideSparkSectionsForDeterministicPopoverRendering() async {
        let client = FakeScreenshotClient()
        let store = RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "spark"],
            environment: [:],
            clientFactory: { client }
        )

        await store.start()

        XCTAssertEqual(store.visibleCardSections(visibleSupplementalFamilyIDs: []).map(\.familyId), ["codex"])
        XCTAssertEqual(store.visibleCardSections(visibleSupplementalFamilyIDs: []).map(\.title), [nil])
    }
}

private final class FakeScreenshotClient: @unchecked Sendable, CodexRateLimitClient {
    private(set) var loadSnapshotCallCount = 0
    private(set) var connectCallCount = 0

    func events() -> AsyncStream<CodexAppServerEvent> {
        AsyncStream { _ in }
    }

    func connect() async throws {
        connectCallCount += 1
    }

    func disconnect() async {}

    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse {
        GetAccountResponse(account: nil, requiresOpenaiAuth: false)
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: nil,
                limitName: nil,
                planType: nil,
                primary: nil,
                secondary: nil
            ),
            rateLimitsByLimitId: nil
        )
    }

    func readLoginStatus() async throws -> CodexLoginStatus {
        .loggedIn
    }

    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        loadSnapshotCallCount += 1
        return (try await readAccount(refreshToken: refreshToken), try await readRateLimits())
    }

}
