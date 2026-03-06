import Foundation
import XCTest
@testable import CodexToolbar

@MainActor
final class RateLimitStoreTests: XCTestCase {
    func testMakeCardsSortsHighestUsedFirstAndMarksPrimary() {
        let snapshot = CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex",
            limitName: "Codex",
            planType: .pro,
            primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 88, windowDurationMins: 300),
            secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 92, windowDurationMins: 10080)
        )

        let cards = RateLimitStore.makeCards(from: snapshot)

        XCTAssertEqual(cards.map(\.usedPercent), [92, 88])
        XCTAssertTrue(cards[0].isPrimary)
        XCTAssertFalse(cards[1].isPrimary)
        XCTAssertEqual(cards[0].title, "Weekly")
    }

    func testReconnectsAfterDisconnectEvent() async {
        let client = FakeCodexRateLimitClient()
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 50_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()
        XCTAssertEqual(client.loadSnapshotCallCount, 1)

        client.emit(.disconnected("Codex app-server exited with status 1."))
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(client.loadSnapshotCallCount, 2)
    }

    func testPeriodicRefreshLoadsSnapshotAgain() async {
        let client = FakeCodexRateLimitClient()
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 50_000_000 }
        )

        await store.start()
        try? await Task.sleep(nanoseconds: 140_000_000)

        XCTAssertGreaterThanOrEqual(client.loadSnapshotCallCount, 2)
        await store.stop()
    }

    func testDefaultRefreshDelayAlignsToNextMinuteBoundary() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 6,
            hour: 12,
            minute: 34,
            second: 45,
            nanosecond: 250_000_000
        ))!
        let delay = RateLimitStore.defaultRefreshDelayNanoseconds(now: now, calendar: calendar)

        XCTAssertEqual(delay, 14_750_000_000)
    }
}

private final class FakeCodexRateLimitClient: @unchecked Sendable, CodexRateLimitClient {
    private var continuation: AsyncStream<CodexAppServerEvent>.Continuation?
    private lazy var stream: AsyncStream<CodexAppServerEvent> = AsyncStream { continuation in
        self.continuation = continuation
    }

    private(set) var connectCallCount = 0
    private(set) var loadSnapshotCallCount = 0

    func events() -> AsyncStream<CodexAppServerEvent> {
        stream
    }

    func connect() async throws {
        connectCallCount += 1
    }

    func disconnect() async {}

    func readAccount() async throws -> GetAccountResponse {
        GetAccountResponse(account: .chatgpt(email: "mike@example.com", planType: .pro), requiresOpenaiAuth: false)
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 88, windowDurationMins: 300),
                secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 92, windowDurationMins: 10080)
            ),
            rateLimitsByLimitId: nil
        )
    }

    func loadSnapshot() async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        loadSnapshotCallCount += 1
        return (try await readAccount(), try await readRateLimits())
    }

    func emit(_ event: CodexAppServerEvent) {
        continuation?.yield(event)
    }
}
