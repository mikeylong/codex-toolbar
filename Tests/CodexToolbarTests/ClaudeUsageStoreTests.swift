import Foundation
import XCTest
@testable import CodexToolbar

@MainActor
final class ClaudeUsageStoreTests: XCTestCase {
    func testStatusBarUsesMostConstrainedCoreWindowAndExcludesModelLimits() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            ClaudeUsageWindow(id: "session", title: "Session", usedPercent: 60, resetDescription: "Resets at 3pm"),
            ClaudeUsageWindow(id: "weekly", title: "Weekly", usedPercent: 25, resetDescription: nil),
            ClaudeUsageWindow(id: "weekly-fable", title: "Weekly (Fable)", usedPercent: 100, resetDescription: nil)
        ])
        let store = ClaudeUsageStore(initialSnapshot: snapshot, liveUpdatesEnabled: false)

        XCTAssertEqual(store.statusItemPresentation, .bar(.init(remainingPercent: 40, progressState: .normal)))
        XCTAssertEqual(store.statusItemTooltipText, "Claude · Session: 40% remaining. Resets at 3pm")
        XCTAssertEqual(store.statusBarAccessibilityText, store.statusItemTooltipText)
    }

    func testStatusBarUsesWeeklyWhenMoreConstrainedThanSession() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            ClaudeUsageWindow(id: "session", title: "Session", usedPercent: 10, resetDescription: nil),
            ClaudeUsageWindow(id: "weekly", title: "Weekly", usedPercent: 95, resetDescription: nil)
        ])
        let store = ClaudeUsageStore(initialSnapshot: snapshot, liveUpdatesEnabled: false)

        XCTAssertEqual(store.statusItemPresentation, .bar(.init(remainingPercent: 5, progressState: .critical)))
        XCTAssertEqual(store.statusItemTooltipText, "Claude · Weekly: 5% remaining")
    }

    func testStatusBarDoesNotSubstituteModelSpecificLimitForMissingCoreWindow() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            ClaudeUsageWindow(id: "weekly-fable", title: "Weekly (Fable)", usedPercent: 100, resetDescription: nil)
        ])
        let store = ClaudeUsageStore(initialSnapshot: snapshot, liveUpdatesEnabled: false)

        XCTAssertEqual(store.statusItemPresentation, .text("--"))
        XCTAssertEqual(store.statusItemTooltipText, "Claude: Core usage limits unavailable.")
    }

    func testInitialStatusBarShowsLoadingWithoutInventingUsage() {
        let store = ClaudeUsageStore(liveUpdatesEnabled: false)

        XCTAssertEqual(store.statusItemPresentation, .text("--"))
        XCTAssertEqual(store.statusItemTooltipText, "Claude: Loading Claude usage…")
    }

    func testSuccessUsesCLIWindowsAndRefreshTimestamp() async {
        let snapshot = Self.snapshot(usedPercent: 28)
        let client = StoreClaudeUsageClient(outcomes: [.success(snapshot)])
        let now = Date(timeIntervalSince1970: 1_000)
        let store = ClaudeUsageStore(client: client, nowProvider: { now })

        await store.refreshNow()

        XCTAssertEqual(store.windows, snapshot.windows)
        XCTAssertEqual(store.lastUpdated, now)
        XCTAssertNil(store.statusMessage)
        XCTAssertFalse(store.isStale)
        XCTAssertFalse(store.isLoading)
    }

    func testTransientFailurePreservesLastKnownUsageAndTimestampThenRecovers() async {
        let first = Self.snapshot(usedPercent: 28)
        let second = Self.snapshot(usedPercent: 42)
        let client = StoreClaudeUsageClient(outcomes: [
            .success(first), .failure(TemporaryClaudeUsageError()), .success(second)
        ])
        let clock = ClaudeUsageTestClock(Date(timeIntervalSince1970: 1_000))
        let store = ClaudeUsageStore(client: client, nowProvider: { clock.now })
        await store.refreshNow()
        clock.now = Date(timeIntervalSince1970: 1_100)

        await store.refreshNow()

        XCTAssertEqual(store.windows, first.windows)
        XCTAssertEqual(store.lastUpdated, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(store.statusMessage, "Connection unavailable.")
        XCTAssertTrue(store.isStale)
        XCTAssertEqual(store.statusItemPresentation, .text("!"))
        XCTAssertTrue(store.statusItemTooltipText.contains("Claude usage is stale."))
        XCTAssertTrue(store.statusItemTooltipText.contains("Last known Current session: 72% remaining."))

        await store.refreshNow()

        XCTAssertEqual(store.windows, second.windows)
        XCTAssertEqual(store.lastUpdated, clock.now)
        XCTAssertNil(store.statusMessage)
        XCTAssertFalse(store.isStale)
        XCTAssertEqual(store.statusItemPresentation, .bar(.init(remainingPercent: 58, progressState: .normal)))
    }

    func testAuthenticationFailureClearsCachedAccountUsage() async {
        let client = StoreClaudeUsageClient(outcomes: [
            .success(Self.snapshot(usedPercent: 28)), .failure(ClaudeUsageError.notAuthenticated)
        ])
        let store = ClaudeUsageStore(client: client)
        await store.refreshNow()

        await store.refreshNow()

        XCTAssertTrue(store.windows.isEmpty)
        XCTAssertNil(store.lastUpdated)
        XCTAssertEqual(store.statusMessage, ClaudeUsageError.notAuthenticated.localizedDescription)
        XCTAssertFalse(store.isStale)
        XCTAssertEqual(store.statusItemPresentation, .text("!"))
        XCTAssertEqual(store.statusItemTooltipText, "Claude: \(ClaudeUsageError.notAuthenticated.localizedDescription)")
    }

    func testRefreshIfNeededUsesFiveMinuteFreshnessThreshold() async {
        let client = StoreClaudeUsageClient(outcomes: [
            .success(Self.snapshot(usedPercent: 28)), .success(Self.snapshot(usedPercent: 29))
        ])
        let clock = ClaudeUsageTestClock(Date(timeIntervalSince1970: 1_000))
        let store = ClaudeUsageStore(client: client, nowProvider: { clock.now })
        await store.refreshNow()
        clock.now = Date(timeIntervalSince1970: 1_299)
        await store.refreshIfNeeded()
        let freshCallCount = await client.callCount
        XCTAssertEqual(freshCallCount, 1)

        clock.now = Date(timeIntervalSince1970: 1_300)
        await store.refreshIfNeeded()

        let staleCallCount = await client.callCount
        XCTAssertEqual(staleCallCount, 2)
        XCTAssertEqual(store.windows.first?.usedPercent, 29)
    }

    func testSwitchToAPIAuthenticationClearsCachedSubscriptionUsage() async {
        let client = StoreClaudeUsageClient(outcomes: [
            .success(Self.snapshot(usedPercent: 28)), .failure(ClaudeUsageError.notSubscription)
        ])
        let store = ClaudeUsageStore(client: client)
        await store.refreshNow()

        await store.refreshNow()

        XCTAssertTrue(store.windows.isEmpty)
        XCTAssertNil(store.lastUpdated)
        XCTAssertEqual(store.statusMessage, ClaudeUsageError.notSubscription.localizedDescription)
        XCTAssertFalse(store.isStale)
    }

    func testConcurrentRefreshesShareOneCLIRequest() async {
        let client = StoreClaudeUsageClient(outcomes: [.suspended])
        let store = ClaudeUsageStore(client: client)
        let first = Task { await store.refreshNow() }
        await waitForCalls(1, client: client)
        let second = Task { await store.refreshNow() }
        for _ in 0..<10 { await Task.yield() }

        await client.completeSuspended(with: Self.snapshot(usedPercent: 28))
        await first.value
        await second.value

        let callCount = await client.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.windows.first?.usedPercent, 28)
    }

    func testStopWaitsForRequestAndRejectsItsLateResult() async {
        let initial = Self.snapshot(usedPercent: 10)
        let client = StoreClaudeUsageClient(outcomes: [.suspended])
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let store = ClaudeUsageStore(client: client, initialSnapshot: initial, initialLastUpdated: timestamp)
        let refresh = Task { await store.refreshNow() }
        await waitForCalls(1, client: client)
        let stop = Task { await store.stop() }
        while store.isLoading { await Task.yield() }

        await client.completeSuspended(with: Self.snapshot(usedPercent: 99))
        await refresh.value
        await stop.value

        XCTAssertEqual(store.windows, initial.windows)
        XCTAssertEqual(store.lastUpdated, timestamp)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.statusMessage)
    }

    func testRefreshAfterStopSerializesBehindCancelledRequest() async {
        let client = StoreClaudeUsageClient(outcomes: [
            .suspended, .success(Self.snapshot(usedPercent: 42))
        ])
        let store = ClaudeUsageStore(client: client)
        let first = Task { await store.refreshNow() }
        await waitForCalls(1, client: client)
        let stop = Task { await store.stop() }
        while store.isLoading { await Task.yield() }
        let replacement = Task { await store.refreshNow() }
        for _ in 0..<10 { await Task.yield() }

        await client.completeSuspended(with: Self.snapshot(usedPercent: 99))
        await first.value
        await stop.value
        await replacement.value

        let callCount = await client.callCount
        let maximumConcurrentRequests = await client.maximumConcurrentRequests
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(maximumConcurrentRequests, 1)
        XCTAssertEqual(store.windows.first?.usedPercent, 42)
    }

    func testStaticScreenshotStoreDoesNotStartLiveRequests() async {
        let client = StoreClaudeUsageClient(outcomes: [])
        let snapshot = Self.snapshot(usedPercent: 28)
        let store = ClaudeUsageStore(client: client, initialSnapshot: snapshot, liveUpdatesEnabled: false)

        await store.start()
        await store.refreshNow()
        await store.refreshIfNeeded()

        let callCount = await client.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(store.windows, snapshot.windows)
    }

    private func waitForCalls(_ count: Int, client: StoreClaudeUsageClient) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while await client.callCount < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let callCount = await client.callCount
        XCTAssertEqual(callCount, count)
    }

    private static func snapshot(usedPercent: Int) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(windows: [
            ClaudeUsageWindow(
                id: "session",
                title: "Current session",
                usedPercent: usedPercent,
                resetDescription: "Resets Nov 16 at 3pm (America/Los_Angeles)"
            )
        ])
    }
}

private struct TemporaryClaudeUsageError: LocalizedError, Sendable {
    var errorDescription: String? { "Connection unavailable." }
}

private actor StoreClaudeUsageClient: ClaudeUsageClient {
    enum Outcome: Sendable {
        case success(ClaudeUsageSnapshot)
        case failure(any Error)
        case suspended
    }

    private var outcomes: [Outcome]
    private var continuation: CheckedContinuation<ClaudeUsageSnapshot, any Error>?
    private var activeRequests = 0
    private(set) var callCount = 0
    private(set) var maximumConcurrentRequests = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func readUsage() async throws -> ClaudeUsageSnapshot {
        callCount += 1
        activeRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, activeRequests)
        defer { activeRequests -= 1 }
        guard !outcomes.isEmpty else { throw TemporaryClaudeUsageError() }
        switch outcomes.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }

    func completeSuspended(with snapshot: ClaudeUsageSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

private final class ClaudeUsageTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ now: Date) { value = now }

    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
