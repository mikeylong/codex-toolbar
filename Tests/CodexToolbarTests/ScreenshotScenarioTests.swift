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
        XCTAssertEqual(cards[0].title, "Rolling 5-hour window")
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
        XCTAssertEqual(store.lastUpdated, ScreenshotScenario.normal.lastUpdated)
    }
}

private final class FakeScreenshotClient: @unchecked Sendable, CodexRateLimitClient {
    private(set) var loadSnapshotCallCount = 0

    func events() -> AsyncStream<CodexAppServerEvent> {
        AsyncStream { _ in }
    }

    func connect() async throws {}

    func disconnect() async {}

    func readAccount() async throws -> GetAccountResponse {
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

    func loadSnapshot() async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        loadSnapshotCallCount += 1
        return (try await readAccount(), try await readRateLimits())
    }
}
