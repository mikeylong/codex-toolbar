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
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalFamilies.first!.limitId
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
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalFamilies.first!.limitId
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

    func testVisibleCardsHideSparkFamilyWhenToggleIsOff() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalFamilies.first!.limitId
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
        let visibleCards = RateLimitStore.visibleCards(from: cards, visibleSupplementalFamilyIDs: [])

        XCTAssertEqual(visibleCards.map(\.familyId), ["codex", "codex"])
        XCTAssertEqual(visibleCards.map(\.title), ["Weekly", "5h"])
    }

    func testVisibleCardSectionsKeepCodexWhenSparkToggleIsOff() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalFamilies.first!.limitId
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

        XCTAssertEqual(store.visibleCardSections(visibleSupplementalFamilyIDs: []).map(\.familyId), ["codex"])
        XCTAssertEqual(store.visibleCardSections(visibleSupplementalFamilyIDs: []).first?.cards.map(\.title), ["Weekly", "5h"])
        XCTAssertEqual(store.statusBarText, "Week: Open")
        XCTAssertEqual(store.statusBarAccessibilityText, "Weekly limit status open. 50% remaining.")
        XCTAssertEqual(store.statusItemTooltipText, "50% remaining")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 50, progressState: .normal))
        )
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

    func testStatusBarTextUsesLowestCoreCodexWindowWhenSparkHasHigherUsage() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalFamilies.first!.limitId
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
        XCTAssertEqual(store.statusBarText, "Week: Open")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 50, progressState: .normal))
        )
    }

    func testStatusBarTextUsesLowestRemainingFiveHourWindowWhenItIsMoreConstrainedThanWeekly() {
        let cards = [
            RateLimitCardViewData(
                window: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 82, windowDurationMins: 300),
                familyId: "codex"
            ),
            RateLimitCardViewData(
                window: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 15, windowDurationMins: 10_080),
                familyId: "codex"
            )
        ]
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .ready,
            initialCards: cards,
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusBarText, "5h: Caution")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 18, progressState: .warning))
        )
        XCTAssertEqual(store.statusBarAccessibilityText, "5-hour limit status caution. 18% remaining.")
        XCTAssertEqual(store.statusItemTooltipText, "18% remaining")
    }

    func testStatusBarTextFallsBackToLowestRemainingCodexDurationWhenWeeklyIsMissing() {
        let cards = [
            RateLimitCardViewData(
                window: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 12, windowDurationMins: 300),
                familyId: "codex"
            ),
            RateLimitCardViewData(
                window: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 41, windowDurationMins: 2_880),
                familyId: "codex"
            )
        ]
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .ready,
            initialCards: cards,
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusBarText, "2d: Open")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 59, progressState: .normal))
        )
    }

    func testStatusBarTextFallsBackToFirstCardWhenNoCodexFamilyExists() {
        let cards = RateLimitStore.makeCards(
            from: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: "codex_unknown",
                limitName: "Unexpected Limit",
                planType: .pro,
                primary: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 73, windowDurationMins: 300),
                secondary: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 21, windowDurationMins: 1_440)
            )
        )
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .ready,
            initialCards: cards,
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusBarText, "5h: Caution")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 27, progressState: .warning))
        )
    }

    func testStatusItemPresentationUsesTextModeWhileConnectingWithoutCards() {
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .connecting,
            initialCards: [],
            initialStatusMessage: "Connecting to Codex…",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusItemPresentation, .text("--"))
        XCTAssertEqual(store.statusItemTooltipText, "Loading rate limits.")
    }

    func testStatusItemPresentationKeepsBarModeWhileConnectingWithCachedCards() {
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .connecting,
            initialCards: [
                RateLimitCardViewData(
                    window: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 82, windowDurationMins: 300),
                    familyId: "codex"
                )
            ],
            initialStatusMessage: "Connecting to Codex…",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 18, progressState: .warning))
        )
        XCTAssertEqual(store.statusBarAccessibilityText, "5-hour limit status caution. 18% remaining.")
        XCTAssertEqual(store.statusItemTooltipText, "18% remaining")
    }

    func testStatusItemPresentationUsesTextModeForErrors() {
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .error("Codex CLI not found."),
            initialCards: [],
            initialStatusMessage: "Codex CLI not found.",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusItemPresentation, .text("!"))
        XCTAssertEqual(store.statusItemTooltipText, "Codex CLI not found.")
    }

    func testStatusItemTooltipUsesUnavailableFallbackWhenReadyWithoutCards() {
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .ready,
            initialCards: [],
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusItemPresentation, .text("--"))
        XCTAssertEqual(store.statusItemTooltipText, "Rate limit status unavailable.")
    }

    func testStatusItemPresentationKeepsExhaustedStateForReadyCards() {
        let store = RateLimitStore(
            client: FakeCodexRateLimitClient(),
            initialState: .ready,
            initialCards: [
                RateLimitCardViewData(
                    window: CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: 100, windowDurationMins: 300),
                    familyId: "codex"
                )
            ],
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )

        XCTAssertEqual(store.statusBarText, "5h: Out")
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 0, progressState: .exhausted))
        )
    }

    func testMakeCardsIgnoresSupplementalBucketsWithNoWindows() {
        let sparkLimitId = GetAccountRateLimitsResponse.supportedSupplementalFamilies.first!.limitId
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
        XCTAssertEqual(store.statusBarAccessibilityText, "Codex app-server connection closed.")
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

    func testManualRefreshKeepsBarPresentationWhileConnectingWithCachedCards() async {
        let client = FakeCodexRateLimitClient()
        let store = RateLimitStore(
            client: client,
            reconnectDelayNanoseconds: 10_000_000_000,
            refreshDelayNanosecondsProvider: { 10_000_000_000 }
        )

        await store.start()
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 8, progressState: .critical))
        )

        client.pauseNextLoadSnapshot = true
        let refreshTask = Task { await store.refreshNow() }
        defer {
            client.resumeLoadSnapshot()
        }

        await waitUntil {
            client.isLoadSnapshotPaused && store.state == .connecting
        }

        XCTAssertEqual(store.state, .connecting)
        XCTAssertEqual(
            store.statusItemPresentation,
            .bar(.init(remainingPercent: 8, progressState: .critical))
        )
        XCTAssertEqual(store.statusBarAccessibilityText, "Weekly limit status tight. 8% remaining.")

        client.resumeLoadSnapshot()
        await refreshTask.value

        XCTAssertEqual(store.state, .ready)
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
    private var loadSnapshotContinuation: CheckedContinuation<Void, Never>?

    private(set) var connectCallCount = 0
    private(set) var loadSnapshotCallCount = 0
    private(set) var readLoginStatusCallCount = 0
    private(set) var readRateLimitsCallCount = 0
    private(set) var readAccountRefreshTokens: [Bool] = []
    private(set) var isLoadSnapshotPaused = false
    var failReadRateLimits: Error?
    var loadSnapshotError: Error?
    var loginStatusResults: [Result<CodexLoginStatus, Error>] = []
    var accountResponse = GetAccountResponse(account: .chatgpt(email: "mike@example.com", planType: .pro), requiresOpenaiAuth: false)
    var pauseNextLoadSnapshot = false
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

        if pauseNextLoadSnapshot {
            pauseNextLoadSnapshot = false
            isLoadSnapshotPaused = true
            await withCheckedContinuation { continuation in
                loadSnapshotContinuation = continuation
            }
            isLoadSnapshotPaused = false
        }

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

    func resumeLoadSnapshot() {
        loadSnapshotContinuation?.resume()
        loadSnapshotContinuation = nil
    }
}
