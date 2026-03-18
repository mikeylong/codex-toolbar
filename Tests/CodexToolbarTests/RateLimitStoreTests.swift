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
            secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 92, windowDurationMins: 10_080)
        )

        let cards = RateLimitStore.makeCards(from: snapshot)

        XCTAssertEqual(cards.map(\.usedPercent), [92, 88])
        XCTAssertTrue(cards[0].isPrimary)
        XCTAssertFalse(cards[1].isPrimary)
        XCTAssertEqual(cards[0].compactLabel, "Weekly")
        XCTAssertEqual(cards[0].title, "Weekly")
    }

    func testMakeCardsFromResponsePreservesLegacyOutputForCodexOnlySnapshots() {
        let response = GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 88, windowDurationMins: 300),
                secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 92, windowDurationMins: 10_080)
            ),
            rateLimitsByLimitId: nil
        )

        let cards = RateLimitStore.makeCards(from: response)

        XCTAssertEqual(cards.map(\.title), ["Weekly", "5h"])
        XCTAssertEqual(cards.map(\.compactLabel), ["Weekly", "5h"])
    }

    func testMakeCardsIncludesSparkBucketWhenPresentAndAvoidsDuplicateCodexEntries() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalLimitOrder.first!
        let response = GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 40, windowDurationMins: 300),
                secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 50, windowDurationMins: 10_080)
            ),
            rateLimitsByLimitId: [
                sparkLimitId: CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: sparkLimitId,
                    limitName: "GPT-5.3-Codex-Spark",
                    planType: .pro,
                    primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 82, windowDurationMins: 300),
                    secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 15, windowDurationMins: 20_160)
                ),
                "codex": CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: "codex",
                    limitName: "Codex",
                    planType: .pro,
                    primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 12, windowDurationMins: 300),
                    secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 17, windowDurationMins: 10_080)
                )
            ]
        )

        let cards = RateLimitStore.makeCards(from: response)

        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(cards.filter { $0.displayTitle.hasPrefix("GPT-5.3-Codex-Spark · ") }.count, 2)
        XCTAssertEqual(cards.filter { $0.displayTitle == "5h" }.count, 1)
        XCTAssertEqual(cards.filter { $0.displayTitle == "Weekly" }.count, 1)
    }

    func testMakeCardSectionsGroupFamiliesWithCodexFirst() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalLimitOrder.first!
        let response = GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 40, windowDurationMins: 300),
                secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 50, windowDurationMins: 10_080)
            ),
            rateLimitsByLimitId: [
                sparkLimitId: CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: sparkLimitId,
                    limitName: "GPT-5.3-Codex-Spark",
                    planType: .pro,
                    primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 82, windowDurationMins: 300),
                    secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 15, windowDurationMins: 20_160)
                )
            ]
        )

        let cards = RateLimitStore.makeCards(from: response)
        let sections = RateLimitStore.makeCardSections(from: cards)

        XCTAssertEqual(cards.first?.displayTitle, "GPT-5.3-Codex-Spark · 5h")
        XCTAssertEqual(sections.map(\.familyId), ["codex", sparkLimitId])
        XCTAssertEqual(sections.map(\.title), [nil, "GPT-5.3-Codex-Spark limit"])
        XCTAssertEqual(sections.map(\.isGrouped), [true, true])
        XCTAssertEqual(sections.map(\.showsTitle), [false, true])
        XCTAssertEqual(sections[0].cards.map(\.title), ["5h", "Weekly"])
        XCTAssertEqual(sections[1].cards.map(\.title), ["5h", "2 Week"])
    }

    func testMakeCardSectionsKeepsSingleFamilyLayoutUngrouped() {
        let snapshot = CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex",
            limitName: "Codex",
            planType: .pro,
            primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 88, windowDurationMins: 300),
            secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 92, windowDurationMins: 10_080)
        )

        let cards = RateLimitStore.makeCards(from: snapshot)
        let sections = RateLimitStore.makeCardSections(from: cards)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].familyId, "codex")
        XCTAssertNil(sections[0].title)
        XCTAssertFalse(sections[0].isGrouped)
        XCTAssertFalse(sections[0].showsTitle)
        XCTAssertEqual(sections[0].cards, cards)
    }

    func testStatusBarTextStillUsesGlobalPrimaryWhenCodexSectionIsShownFirst() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalLimitOrder.first!
        let response = GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 40, windowDurationMins: 300),
                secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 50, windowDurationMins: 10_080)
            ),
            rateLimitsByLimitId: [
                sparkLimitId: CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: sparkLimitId,
                    limitName: "GPT-5.3-Codex-Spark",
                    planType: .pro,
                    primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 82, windowDurationMins: 300),
                    secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 15, windowDurationMins: 20_160)
                )
            ]
        )

        let cards = RateLimitStore.makeCards(from: response)
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .ready,
            initialCards: cards,
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.cardSections.first?.title, nil)
        XCTAssertEqual(store.statusBarText, "18% 5h")
    }

    func testMakeCardsIgnoresSupplementalBucketsWithNoWindows() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalLimitOrder.first!
        let response = GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 40, windowDurationMins: 300),
                secondary: nil
            ),
            rateLimitsByLimitId: [
                sparkLimitId: CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: sparkLimitId,
                    limitName: "GPT-5.3-Codex-Spark",
                    planType: .pro,
                    primary: nil,
                    secondary: nil
                )
            ]
        )

        let cards = RateLimitStore.makeCards(from: response)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "5h")
    }

    func testMakeCardsIgnoresUnknownSupplementalBucketIds() {
        let response = GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex",
                limitName: "Codex",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 40, windowDurationMins: 300),
                secondary: nil
            ),
            rateLimitsByLimitId: [
                "codex_unknown": CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: "codex_unknown",
                    limitName: "Unknown Spark",
                    planType: .pro,
                    primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 99, windowDurationMins: 300),
                    secondary: nil
                )
            ]
        )

        let cards = RateLimitStore.makeCards(from: response)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "5h")
    }

    func testMakeCardsUsesWeeklyForOffByOneCoreCodexSecondaryBucket() {
        let snapshot = CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex",
            limitName: "Codex",
            planType: .pro,
            primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 12, windowDurationMins: 300),
            secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 41, windowDurationMins: 10_081)
        )

        let cards = RateLimitStore.makeCards(from: snapshot)

        XCTAssertEqual(cards[0].compactLabel, "Weekly")
        XCTAssertEqual(cards[0].title, "Weekly")
    }

    func testMakeCardsKeepsNonCodexFormatterLabels() {
        let snapshot = CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex_bengalfox",
            limitName: "GPT-5.3-Codex-Spark",
            planType: .pro,
            primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 12, windowDurationMins: 300),
            secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 41, windowDurationMins: 20_160)
        )

        let cards = RateLimitStore.makeCards(from: snapshot)

        XCTAssertEqual(cards[0].compactLabel, "2 Week")
        XCTAssertEqual(cards[0].title, "2 Week")
    }

    func testReconnectsAfterDisconnectEvent() async {
        let client = FakeCodexRateLimitClient()
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 50_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()
        XCTAssertEqual(client.connectCallCount, 1)
        XCTAssertEqual(client.loadSnapshotCallCount, 1)

        client.emit(.disconnected("Codex app-server exited with status 1."))
        await waitUntil {
            client.connectCallCount >= 2 && client.loadSnapshotCallCount >= 2
        }

        XCTAssertGreaterThanOrEqual(client.connectCallCount, 2)
        XCTAssertGreaterThanOrEqual(client.loadSnapshotCallCount, 2)
        XCTAssertEqual(store.state, .ready)

        await store.stop()
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

        XCTAssertGreaterThanOrEqual(client.connectCallCount, 1)
        XCTAssertGreaterThanOrEqual(client.loadSnapshotCallCount, 2)
        await store.stop()
    }

    func testManualRefreshFailurePreservesCardsAndShowsErrorState() async {
        let client = FakeCodexRateLimitClient()
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()
        let initialLastUpdated = store.lastUpdated
        client.failReadRateLimits = CodexAppServerError.transportClosed

        await store.refreshNow()

        XCTAssertEqual(store.state, .error("Codex app-server connection closed."))
        XCTAssertFalse(store.cards.isEmpty)
        XCTAssertEqual(store.staleMessage, "Codex app-server connection closed.")
        XCTAssertEqual(store.statusBarText, "!")
        XCTAssertEqual(store.lastUpdated, initialLastUpdated)
    }

    func testManualRefreshRequestsTokenRefresh() async {
        let client = FakeCodexRateLimitClient()
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()
        let refreshTokensBeforeManualRefresh = client.readAccountRefreshTokens.count

        await store.refreshNow()

        XCTAssertEqual(Array(client.readAccountRefreshTokens.dropFirst(refreshTokensBeforeManualRefresh)), [true])
    }

    func testStartupLoggedOutPreflightShowsSignInWithoutSnapshot() async {
        let client = FakeCodexRateLimitClient()
        client.loginStatusResults = [.success(.loggedOut)]
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()

        XCTAssertEqual(store.state, .error("Sign in to Codex to view rate limits."))
        XCTAssertEqual(client.loadSnapshotCallCount, 0)
        XCTAssertGreaterThanOrEqual(client.readLoginStatusCallCount, 1)
    }

    func testStartupCodexCLINotFoundWinsBeforeAuthHandling() async {
        let client = FakeCodexRateLimitClient()
        client.loginStatusResults = [.failure(CodexAppServerError.codexCLINotFound)]
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()

        XCTAssertEqual(store.state, .error("Codex CLI not found."))
        XCTAssertEqual(store.statusMessage, "Codex CLI not found.")
        XCTAssertEqual(client.loadSnapshotCallCount, 0)
    }

    func testManualRefreshLoggedOutPreflightSkipsSnapshot() async {
        let client = FakeCodexRateLimitClient()
        client.loginStatusResults = [.success(.loggedIn), .success(.loggedOut)]
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()
        XCTAssertEqual(client.loadSnapshotCallCount, 1)

        await store.refreshNow()

        XCTAssertEqual(store.state, .error("Sign in to Codex to view rate limits."))
        XCTAssertEqual(client.loadSnapshotCallCount, 1)
        XCTAssertEqual(client.readLoginStatusCallCount, 2)
    }

    func testTimerRefreshPreflightsWhenAlreadyShowingSignInError() async {
        let client = FakeCodexRateLimitClient()
        client.loginStatusResults = Array(repeating: .success(.loggedOut), count: 6)
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 50_000_000 }
        )

        await store.start()
        await waitUntil {
            store.state == .error("Sign in to Codex to view rate limits.")
                && client.readLoginStatusCallCount >= 2
        }

        XCTAssertEqual(store.state, .error("Sign in to Codex to view rate limits."))
        XCTAssertEqual(client.loadSnapshotCallCount, 0)
        XCTAssertGreaterThanOrEqual(client.readLoginStatusCallCount, 2)
    }

    func testTimeoutFallbackMapsLoggedOutStateToSignIn() async {
        let client = FakeCodexRateLimitClient()
        client.loginStatusResults = [.success(.loggedIn), .success(.loggedOut)]
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 50_000_000 }
        )

        await store.start()
        client.loadSnapshotError = CodexAppServerError.serverError("Timed out reading Codex rate limits.")
        let initialCards = store.cards

        await waitUntil {
            store.statusMessage == "Sign in to Codex to view rate limits."
                && client.loadSnapshotCallCount >= 2
        }

        XCTAssertEqual(store.statusMessage, "Sign in to Codex to view rate limits.")
        XCTAssertEqual(store.staleMessage, "Sign in to Codex to view rate limits.")
        XCTAssertEqual(store.cards, initialCards)
        XCTAssertEqual(client.readLoginStatusCallCount, 2)
    }

    func testStartupIgnoresRequiresOpenaiAuthWhenAccountIsPresent() async {
        let client = FakeCodexRateLimitClient()
        client.accountResponse = GetAccountResponse(
            account: .chatgpt(email: "mike@example.com", planType: .pro),
            requiresOpenaiAuth: true
        )
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()

        XCTAssertEqual(store.state, .ready)
        XCTAssertFalse(store.cards.isEmpty)
        XCTAssertEqual(store.statusMessage, "Rate limits remaining")
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

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))

        while ContinuousClock.now < deadline {
            if condition() {
                return
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        XCTFail("Timed out waiting for condition.", file: file, line: line)
    }
}

private final class FakeCodexRateLimitClient: @unchecked Sendable, CodexRateLimitClient {
    private var continuation: AsyncStream<CodexAppServerEvent>.Continuation?
    private lazy var stream: AsyncStream<CodexAppServerEvent> = AsyncStream { continuation in
        self.continuation = continuation
    }

    private(set) var connectCallCount = 0
    private(set) var loadSnapshotCallCount = 0
    private(set) var readLoginStatusCallCount = 0
    private(set) var readRateLimitsCallCount = 0
    private(set) var readAccountRefreshTokens: [Bool] = []
    var failReadRateLimits: Error?
    var loadSnapshotError: Error?
    var loginStatusResults: [Result<CodexLoginStatus, Error>] = []
    var accountResponse = GetAccountResponse(account: .chatgpt(email: "mike@example.com", planType: .pro), requiresOpenaiAuth: false)
    private var isConnected = false

    func events() -> AsyncStream<CodexAppServerEvent> {
        stream
    }

    func connect() async throws {
        guard !isConnected else { return }
        isConnected = true
        connectCallCount += 1
    }

    func disconnect() async {
        isConnected = false
    }

    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse {
        readAccountRefreshTokens.append(refreshToken)
        return accountResponse
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        readRateLimitsCallCount += 1

        if let failReadRateLimits {
            throw failReadRateLimits
        }

        return GetAccountRateLimitsResponse(
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

    func readLoginStatus() async throws -> CodexLoginStatus {
        readLoginStatusCallCount += 1

        if !loginStatusResults.isEmpty {
            return try loginStatusResults.removeFirst().get()
        }

        return .loggedIn
    }

    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        loadSnapshotCallCount += 1

        if let loadSnapshotError {
            throw loadSnapshotError
        }

        return (try await readAccount(refreshToken: refreshToken), try await readRateLimits())
    }

    func emit(_ event: CodexAppServerEvent) {
        if case .disconnected = event {
            isConnected = false
        }
        continuation?.yield(event)
    }
}
