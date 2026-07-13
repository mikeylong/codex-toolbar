import Foundation
import Observation

@MainActor
@Observable
final class RateLimitStore {
    private static let signInMessage = "Sign in to Codex to view rate limits."
    private static let codexCLINotFoundMessage = "Codex CLI not found."
    private static let noRateLimitDataMessage = "No rate-limit data available."

    private enum WindowRole {
        case primary
        case secondary
    }

    static let shared = makeShared()

    enum State: Equatable {
        case idle
        case connecting
        case ready
        case error(String)
    }

    struct StatusItemBarPresentation: Equatable, Sendable {
        let remainingPercent: Int
        let progressState: RateLimitProgressState
    }

    struct CreditViewData: Equatable, Sendable {
        let balanceText: String?
        let stateText: String
    }

    enum StatusItemPresentation: Equatable, Sendable {
        case text(String)
        case bar(StatusItemBarPresentation)
    }

    var state: State = .idle
    var cards: [RateLimitCardViewData] = []
    var creditViewData: CreditViewData?
    var statusMessage = "Connecting to Codex…"
    var lastUpdated: Date?
    var staleMessage: String?
    var debugDetail: String?

    private let client: any CodexRateLimitClient
    private let reconnectDelayNanoseconds: UInt64
    private let refreshDelayNanosecondsProvider: @Sendable () -> UInt64
    private let liveUpdatesEnabled: Bool
    private var started = false
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        client: any CodexRateLimitClient,
        reconnectDelayNanoseconds: UInt64 = 2_000_000_000,
        refreshDelayNanosecondsProvider: @escaping @Sendable () -> UInt64 = { RateLimitStore.defaultRefreshDelayNanoseconds() },
        initialState: State = .idle,
        initialCards: [RateLimitCardViewData] = [],
        initialCreditViewData: CreditViewData? = nil,
        initialStatusMessage: String = "Connecting to Codex…",
        initialLastUpdated: Date? = nil,
        liveUpdatesEnabled: Bool = true
    ) {
        self.client = client
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
        self.refreshDelayNanosecondsProvider = refreshDelayNanosecondsProvider
        self.liveUpdatesEnabled = liveUpdatesEnabled
        state = initialState
        cards = initialCards
        creditViewData = initialCreditViewData
        statusMessage = initialStatusMessage
        lastUpdated = initialLastUpdated
    }

    func start() async {
        guard !started else { return }
        started = true

        guard liveUpdatesEnabled else { return }

        eventTask = Task { [weak self] in
            guard let self else { return }
            let events = client.events()
            for await event in events {
                await handle(event: event)
            }
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshDelayNanosecondsProvider())
                guard !Task.isCancelled else { return }
                await refreshNow(source: .timer)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                debugDetail = "Connecting to Codex app-server"
                try await client.connect()
                if debugDetail == "Connecting to Codex app-server" {
                    debugDetail = "Live updates connected"
                }
            } catch {
                debugDetail = "Connect failed: \(error.localizedDescription)"
                await handleRefreshError(error, preserveCards: !cards.isEmpty)
                scheduleReconnect()
            }
        }

        await refreshNow(source: .startup)
    }

    func stop() async {
        reconnectTask?.cancel()
        eventTask?.cancel()
        refreshTask?.cancel()
        reconnectTask = nil
        eventTask = nil
        refreshTask = nil
        started = false
        await client.disconnect()
    }

    func refreshNow() async {
        await refreshNow(source: .manual)
    }

    var cardSections: [RateLimitCardSectionViewData] {
        Self.makeCardSections(from: cards)
    }

    func visibleCards(visibleSupplementalFamilyIDs: Set<String>) -> [RateLimitCardViewData] {
        Self.visibleCards(from: cards, visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs)
    }

    func visibleCardSections(visibleSupplementalFamilyIDs: Set<String>) -> [RateLimitCardSectionViewData] {
        Self.makeCardSections(from: visibleCards(visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs))
    }

    func visibleCreditViewData(visibleSupplementalFamilyIDs: Set<String>) -> CreditViewData? {
        guard !visibleCards(visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs).isEmpty else {
            return nil
        }

        return creditViewData
    }

    var statusBarText: String {
        switch state {
        case .idle, .connecting:
            return preferredStatusBarCard.map(Self.statusBarText(for:)) ?? "--"
        case .ready:
            return preferredStatusBarCard.map(Self.statusBarText(for:)) ?? "--"
        case .error:
            return "!"
        }
    }

    var statusItemPresentation: StatusItemPresentation {
        switch state {
        case .idle, .connecting, .ready:
            guard let preferredStatusBarCard else {
                return .text("--")
            }

            return .bar(Self.statusItemBarPresentation(for: preferredStatusBarCard))
        case .error:
            return .text("!")
        }
    }

    var statusBarAccessibilityText: String {
        switch state {
        case .idle, .connecting:
            return preferredStatusBarCard.map(Self.statusBarAccessibilityText(for:)) ?? "Loading rate limits."
        case .ready:
            return preferredStatusBarCard.map(Self.statusBarAccessibilityText(for:)) ?? "Rate limit status unavailable."
        case let .error(message):
            return message
        }
    }

    var statusItemTooltipText: String {
        switch state {
        case .idle, .connecting:
            return preferredStatusBarCard.map(Self.statusItemTooltipText(for:)) ?? "Loading rate limits."
        case .ready:
            return preferredStatusBarCard.map(Self.statusItemTooltipText(for:)) ?? "Rate limit status unavailable."
        case let .error(message):
            return message
        }
    }

    private var preferredStatusBarCard: RateLimitCardViewData? {
        Self.preferredStatusBarCard(from: cards)
    }

    private enum RefreshSource {
        case startup
        case timer
        case manual
        case reconnect
    }

    private func refreshNow(source: RefreshSource) async {
        state = .connecting
        if cards.isEmpty || source == .manual {
            statusMessage = "Connecting to Codex…"
        }
        staleMessage = nil
        debugDetail = "Refresh source: \(String(describing: source))"

        do {
            if try await shouldApplyLoggedOutErrorBeforeSnapshot(for: source) {
                return
            }

            let refreshToken = shouldRefreshAccountToken(for: source)
            debugDetail = "Loading snapshot (refreshToken=\(refreshToken))"
            let (account, response) = try await client.loadSnapshot(refreshToken: refreshToken)
            debugDetail = "Snapshot loaded"

            if account.account == nil {
                debugDetail = "No signed-in account"
                applyError(Self.signInMessage)
                return
            }

            apply(response)
        } catch let error as CodexAppServerError {
            await handleRefreshError(error, preserveCards: !cards.isEmpty)
        } catch {
            await handleRefreshError(error, preserveCards: !cards.isEmpty)
        }
    }

    private func handle(event: CodexAppServerEvent) async {
        switch event {
        case let .rateLimitsUpdated(response):
            apply(response)
        case let .disconnected(reason):
            state = .error("Disconnected from Codex.")
            statusMessage = reason ?? "Retrying…"
            staleMessage = cards.isEmpty ? nil : (reason ?? "Disconnected from Codex.")
            scheduleReconnect()
        case .stderr:
            break
        }
    }

    private func apply(_ response: GetAccountRateLimitsResponse) {
        cards = Self.makeCards(from: response)
        creditViewData = Self.makeCreditViewData(from: response.displaySnapshot().credits)
        lastUpdated = Date()

        if cards.isEmpty {
            debugDetail = "Snapshot contained no cards"
            applyError(Self.noRateLimitDataMessage)
            return
        }

        state = .ready
        statusMessage = "Rate limits remaining"
        staleMessage = nil
        debugDetail = "Ready"
    }

    private func applyError(_ message: String) {
        state = .error(message)
        statusMessage = message
        staleMessage = cards.isEmpty ? nil : message
        debugDetail = message

        if message == Self.signInMessage || message == Self.noRateLimitDataMessage {
            cards = []
            staleMessage = nil
        }
    }

    private func handleRefreshError(_ error: Error, preserveCards: Bool) async {
        if await shouldMapToSignInError(error) {
            if preserveCards {
                state = .error(Self.signInMessage)
                statusMessage = Self.signInMessage
                staleMessage = Self.signInMessage
                debugDetail = Self.signInMessage
                scheduleReconnect()
            } else {
                applyError(Self.signInMessage)
                scheduleReconnect()
            }
            return
        }

        let message: String

        if let appServerError = error as? CodexAppServerError {
            switch appServerError {
            case .codexCLINotFound:
                message = Self.codexCLINotFoundMessage
            default:
                message = appServerError.localizedDescription
            }
        } else {
            message = "Unable to load Codex rate limits."
        }

        if preserveCards {
            state = .error(message)
            statusMessage = message
            staleMessage = message
            scheduleReconnect()
        } else {
            applyError(message)
            scheduleReconnect()
        }
    }

    private func shouldApplyLoggedOutErrorBeforeSnapshot(for source: RefreshSource) async throws -> Bool {
        guard shouldPreflightLoginStatus(for: source) else {
            return false
        }

        let loginStatus = try await client.readLoginStatus()
        switch loginStatus {
        case .loggedIn:
            return false
        case .loggedOut:
            debugDetail = "Codex login status: logged out"
            applyError(Self.signInMessage)
            return true
        case let .indeterminate(detail):
            if let detail {
                debugDetail = "Codex login status indeterminate: \(detail)"
            }
            return false
        }
    }

    private func shouldPreflightLoginStatus(for source: RefreshSource) -> Bool {
        switch source {
        case .startup, .manual, .reconnect:
            return true
        case .timer:
            return cards.isEmpty || statusMessage == Self.signInMessage || staleMessage == Self.signInMessage
        }
    }

    private func shouldRefreshAccountToken(for source: RefreshSource) -> Bool {
        switch source {
        case .manual, .reconnect:
            return true
        case .startup, .timer:
            return false
        }
    }

    private func shouldMapToSignInError(_ error: Error) async -> Bool {
        guard isSnapshotTimeout(error) else {
            return false
        }

        do {
            let loginStatus = try await client.readLoginStatus()
            if case .loggedOut = loginStatus {
                debugDetail = "Codex login status fallback: logged out"
                return true
            }
        } catch {
            debugDetail = "Codex login status fallback failed: \(error.localizedDescription)"
        }

        return false
    }

    private func isSnapshotTimeout(_ error: Error) -> Bool {
        guard case let .serverError(message) = error as? CodexAppServerError else {
            return false
        }

        return message.contains("Timed out reading Codex rate limits.")
    }

    static func makeCards(
        from response: GetAccountRateLimitsResponse,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [RateLimitCardViewData] {
        let cardEntries = response.cardCandidates().flatMap { candidate -> [(window: CodexRateLimitWindow, role: WindowRole, categoryLabel: String?, limitId: String)] in
            var entries: [(window: CodexRateLimitWindow, role: WindowRole, categoryLabel: String?, limitId: String)] = []

            if let primary = candidate.snapshot.primary {
                entries.append(
                    (
                        window: primary,
                        role: .primary,
                        categoryLabel: candidate.categoryLabel,
                        limitId: candidate.limitId
                    )
                )
            }

            if let secondary = candidate.snapshot.secondary {
                entries.append(
                    (
                        window: secondary,
                        role: .secondary,
                        categoryLabel: candidate.categoryLabel,
                        limitId: candidate.limitId
                    )
                )
            }

            return entries
        }

        let sorted = cardEntries.sorted {
            if $0.window.usedPercent == $1.window.usedPercent {
                return ($0.window.windowDurationMins ?? .max) < ($1.window.windowDurationMins ?? .max)
            }
            return $0.window.usedPercent > $1.window.usedPercent
        }

        return sorted.enumerated().map { index, entry in
            RateLimitCardViewData(
                window: entry.window,
                displayLabelOverride: displayLabelOverride(
                    role: entry.role,
                    limitId: entry.limitId,
                    windowDurationMins: entry.window.windowDurationMins
                ),
                familyId: entry.limitId,
                categoryLabel: entry.categoryLabel,
                isPrimary: index == 0,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        }
    }

    static func makeCards(
        from snapshot: CodexRateLimitsSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [RateLimitCardViewData] {
        return makeCards(
            from: GetAccountRateLimitsResponse(rateLimits: snapshot, rateLimitsByLimitId: nil),
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    static func makeCreditViewData(from credits: CreditsSnapshot?) -> CreditViewData? {
        guard let credits else {
            return nil
        }

        let trimmedBalance = credits.balance?.trimmingCharacters(in: .whitespacesAndNewlines)
        let balanceText = formattedCreditBalanceText(trimmedBalance)

        let stateText: String
        if credits.unlimited {
            stateText = "Unlimited"
        } else if credits.hasCredits {
            stateText = "Credits available"
        } else {
            stateText = "No credits"
        }

        return CreditViewData(balanceText: balanceText, stateText: stateText)
    }

    private static func formattedCreditBalanceText(_ rawBalance: String?) -> String? {
        guard let rawBalance, !rawBalance.isEmpty else {
            return nil
        }

        let numericPattern = #"^[+-]?(?:\d+\.?\d*|\.\d+)$"#
        guard rawBalance.range(of: numericPattern, options: .regularExpression) != nil else {
            return rawBalance
        }

        guard let decimal = Decimal(string: rawBalance, locale: Locale(identifier: "en_US_POSIX")) else {
            return rawBalance
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        formatter.groupingSeparator = ""

        return formatter.string(from: decimal as NSNumber) ?? rawBalance
    }

    static func makeCardSections(from cards: [RateLimitCardViewData]) -> [RateLimitCardSectionViewData] {
        guard !cards.isEmpty else {
            return []
        }

        let groupedCards = Dictionary(grouping: cards, by: \.familyId)
        guard groupedCards.count > 1 else {
            let familyId = cards.first?.familyId ?? GetAccountRateLimitsResponse.codexLimitId
            return [
                RateLimitCardSectionViewData(
                    familyId: familyId,
                    title: nil,
                    cards: cards,
                    isGrouped: false,
                    showsTitle: false
                )
            ]
        }

        let orderedFamilyIds = groupedCards.keys.sorted { lhs, rhs in
            let lhsRank = familySortRank(for: lhs)
            let rhsRank = familySortRank(for: rhs)

            if lhsRank == rhsRank {
                return lhs < rhs
            }

            return lhsRank < rhsRank
        }

        return orderedFamilyIds.compactMap { familyId in
            guard let sectionCards = groupedCards[familyId], let firstCard = sectionCards.first else {
                return nil
            }

            return RateLimitCardSectionViewData(
                familyId: familyId,
                title: sectionTitle(for: firstCard),
                cards: sortCardsForPopoverSection(sectionCards),
                isGrouped: true,
                showsTitle: familyId != GetAccountRateLimitsResponse.codexLimitId
            )
        }
    }

    static func visibleCards(
        from cards: [RateLimitCardViewData],
        visibleSupplementalFamilyIDs: Set<String>
    ) -> [RateLimitCardViewData] {
        cards.filter { card in
            if card.familyId == GetAccountRateLimitsResponse.codexLimitId {
                return true
            }

            guard let family = GetAccountRateLimitsResponse.supplementalFamily(for: card.familyId) else {
                return false
            }

            if !family.isUserToggleable {
                return true
            }

            return visibleSupplementalFamilyIDs.contains(card.familyId)
        }
    }

    private static func displayLabelOverride(
        role: WindowRole,
        limitId: String?,
        windowDurationMins: Int?
    ) -> String? {
        guard limitId == GetAccountRateLimitsResponse.codexLimitId,
              windowDurationMins == nil
        else {
            return nil
        }

        switch role {
        case .primary:
            return "5h"
        case .secondary:
            return "Weekly"
        }
    }

    private static func familySortRank(for familyId: String) -> Int {
        if familyId == GetAccountRateLimitsResponse.codexLimitId {
            return 0
        }

        if let family = GetAccountRateLimitsResponse.supplementalFamily(for: familyId) {
            return family.sortOrder
        }

        return GetAccountRateLimitsResponse.supportedSupplementalFamilies.count + 1
    }

    private static func sectionTitle(for card: RateLimitCardViewData) -> String? {
        guard card.familyId != GetAccountRateLimitsResponse.codexLimitId else {
            return nil
        }

        return "\(card.familyTitle) limit"
    }

    private static func sortCardsForPopoverSection(_ cards: [RateLimitCardViewData]) -> [RateLimitCardViewData] {
        cards.sorted { lhs, rhs in
            let lhsRank = popoverWindowSortRank(for: lhs)
            let rhsRank = popoverWindowSortRank(for: rhs)

            if lhsRank == rhsRank {
                let lhsDuration = lhs.windowDurationMins ?? .max
                let rhsDuration = rhs.windowDurationMins ?? .max

                if lhsDuration == rhsDuration {
                    return lhs.usedPercent > rhs.usedPercent
                }

                return lhsDuration < rhsDuration
            }

            return lhsRank < rhsRank
        }
    }

    private static func popoverWindowSortRank(for card: RateLimitCardViewData) -> Int {
        guard let duration = card.windowDurationMins else {
            return 3
        }

        if duration == 300 {
            return 0
        }

        if (10_079...10_081).contains(duration) {
            return 1
        }

        return 2
    }

    private static func preferredStatusBarCard(from cards: [RateLimitCardViewData]) -> RateLimitCardViewData? {
        let codexCards = cards.filter { $0.familyId == GetAccountRateLimitsResponse.codexLimitId }
        if let preferredCodexCard = codexCards.sorted(by: isMoreConstrainedStatusBarCard).first {
            return preferredCodexCard
        }

        return cards.first
    }

    private static func statusBarText(for card: RateLimitCardViewData) -> String {
        RateLimitFormatter.statusBarText(
            windowDurationMins: card.windowDurationMins,
            remainingPercent: card.remainingPercent
        )
    }

    private static func statusBarAccessibilityText(for card: RateLimitCardViewData) -> String {
        RateLimitFormatter.statusBarAccessibilityDescription(
            windowDurationMins: card.windowDurationMins,
            remainingPercent: card.remainingPercent
        )
    }

    private static func statusItemTooltipText(for card: RateLimitCardViewData) -> String {
        RateLimitFormatter.statusItemTooltipText(remainingPercent: card.remainingPercent)
    }

    private static func statusItemBarPresentation(for card: RateLimitCardViewData) -> StatusItemBarPresentation {
        StatusItemBarPresentation(
            remainingPercent: card.remainingPercent,
            progressState: card.progressState
        )
    }

    private static func isMoreConstrainedStatusBarCard(_ lhs: RateLimitCardViewData, _ rhs: RateLimitCardViewData) -> Bool {
        if lhs.usedPercent == rhs.usedPercent {
            return (lhs.windowDurationMins ?? .max) < (rhs.windowDurationMins ?? .max)
        }

        return lhs.usedPercent > rhs.usedPercent
    }

    static func makeShared(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        clientFactory: @escaping () -> any CodexRateLimitClient = { CodexAppServerClient() }
    ) -> RateLimitStore {
        if let launchConfiguration = ScreenshotLaunchConfiguration.current(arguments: arguments, environment: environment) {
            let cards = makeCards(
                from: launchConfiguration.scenario.rateLimitsResponse,
                now: launchConfiguration.scenario.now,
                calendar: launchConfiguration.scenario.calendar,
                locale: launchConfiguration.scenario.locale,
                timeZone: launchConfiguration.scenario.timeZone
            )
            let statusMessage = cards.isEmpty ? "No rate-limit data available." : "Rate limits remaining"
            let state: State = cards.isEmpty ? .error(statusMessage) : .ready

            return RateLimitStore(
                client: clientFactory(),
                initialState: state,
                initialCards: cards,
                initialStatusMessage: statusMessage,
                initialLastUpdated: launchConfiguration.scenario.lastUpdated,
                liveUpdatesEnabled: false
            )
        }

        return RateLimitStore(client: clientFactory())
    }

    nonisolated static func defaultRefreshDelayNanoseconds(now: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        let currentSecond = calendar.component(.second, from: now)
        let currentNanosecond = calendar.component(.nanosecond, from: now)

        let remainingSeconds = max(0, 59 - currentSecond)
        let remainingNanoseconds = max(0, 1_000_000_000 - currentNanosecond)
        let totalNanoseconds = UInt64(remainingSeconds) * 1_000_000_000 + UInt64(remainingNanoseconds)

        return max(totalNanoseconds, 1_000_000)
    }

    private func scheduleReconnect() {
        guard started else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
            guard !Task.isCancelled else { return }
            do {
                try await client.connect()
            } catch {
                await handleRefreshError(error, preserveCards: !cards.isEmpty)
                scheduleReconnect()
                return
            }
            await refreshNow(source: .reconnect)
        }
    }
}
