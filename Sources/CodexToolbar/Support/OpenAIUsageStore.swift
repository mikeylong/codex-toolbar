import Foundation
import Observation

@MainActor
@Observable
final class OpenAIUsageStore {
    struct PeriodSummaryViewData: Equatable, Sendable {
        let title: String
        let primaryText: String?
        let secondaryText: String?
    }

    struct ViewData: Equatable, Sendable {
        let statusMessage: String?
        let periodSummaries: [PeriodSummaryViewData]
        let costsStatusMessage: String?
        let usageStatusMessage: String?
        let footerText: String?
    }

    private struct QueryWindow {
        let startTime: Int64
        let endTime: Int64
        let limit: Int
    }

    private enum FetchResult<T: Sendable>: Sendable {
        case success(T)
        case failure(String)
    }

    nonisolated static let staleRefreshMaximumAge: TimeInterval = 60

    let isEnabled: Bool
    private(set) var hasConfiguredAdminKey = false
    private(set) var isLoading = false

    private let client: any OpenAIUsageClient
    private let adminKeyStore: any OpenAIAdminKeyStore
    private let refreshDelayNanosecondsProvider: @Sendable () -> UInt64
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let timeZone: TimeZone

    private var cachedCostBuckets: [OpenAICostBucket]?
    private var cachedUsageBuckets: [OpenAICompletionsUsageBucket]?
    private var costsLastUpdated: Date?
    private var usageLastUpdated: Date?
    private var costsFailureMessage: String?
    private var usageFailureMessage: String?
    private var generalStatusMessage: String?
    private var started = false
    private var refreshTask: Task<Void, Never>?

    init(
        client: any OpenAIUsageClient = LiveOpenAIUsageClient(),
        adminKeyStore: any OpenAIAdminKeyStore = KeychainOpenAIAdminKeyStore(),
        refreshDelayNanosecondsProvider: @escaping @Sendable () -> UInt64 = { OpenAIUsageStore.defaultRefreshDelayNanoseconds() },
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        isEnabled: Bool = false
    ) {
        self.client = client
        self.adminKeyStore = adminKeyStore
        self.refreshDelayNanosecondsProvider = refreshDelayNanosecondsProvider
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
        self.isEnabled = isEnabled

        guard isEnabled else {
            return
        }

        hasConfiguredAdminKey = ((try? adminKeyStore.readAdminKey())?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        if !hasConfiguredAdminKey {
            generalStatusMessage = Self.missingKeyMessage
        }
    }

    var viewData: ViewData? {
        guard isEnabled else {
            return nil
        }

        let snapshot = Self.snapshot(
            fromCosts: cachedCostBuckets,
            usageBuckets: cachedUsageBuckets,
            now: nowProvider(),
            calendar: calendar
        )

        let periodSummaries = snapshot.map { snapshot in
            Self.makePeriodSummaries(from: snapshot, locale: locale)
        } ?? []

        return ViewData(
            statusMessage: generalStatusMessage,
            periodSummaries: periodSummaries,
            costsStatusMessage: endpointStatusMessage(
                label: "Costs",
                failureMessage: costsFailureMessage,
                hasCachedData: cachedCostBuckets != nil
            ),
            usageStatusMessage: endpointStatusMessage(
                label: "Usage",
                failureMessage: usageFailureMessage,
                hasCachedData: cachedUsageBuckets != nil
            ),
            footerText: lastUpdated.map {
                RateLimitFormatter.updatedFooterText(for: $0, locale: locale, timeZone: timeZone)
            }
        )
    }

    private var lastUpdated: Date? {
        [costsLastUpdated, usageLastUpdated].compactMap { $0 }.max()
    }

    func start() async {
        guard isEnabled, !started else { return }
        started = true

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshDelayNanosecondsProvider())
                guard !Task.isCancelled else { return }
                await refreshNow()
            }
        }

        await refreshNow()
    }

    func stop() async {
        refreshTask?.cancel()
        refreshTask = nil
        started = false
    }

    func refreshIfNeeded(maxAge: TimeInterval) async {
        guard isEnabled else { return }

        if let lastUpdated, nowProvider().timeIntervalSince(lastUpdated) < maxAge {
            return
        }

        await refreshNow()
    }

    func refreshNow() async {
        guard isEnabled else { return }

        let hadCachedData = cachedCostBuckets != nil || cachedUsageBuckets != nil

        let adminKey: String
        do {
            guard let storedKey = try adminKeyStore.readAdminKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !storedKey.isEmpty else {
                clearForMissingAdminKey()
                return
            }

            adminKey = storedKey
            hasConfiguredAdminKey = true
        } catch {
            hasConfiguredAdminKey = false
            isLoading = false
            generalStatusMessage = hadCachedData
                ? "OpenAI admin key unavailable. Showing last known API usage."
                : "Unable to access the OpenAI admin key."
            return
        }

        isLoading = true
        if !hadCachedData {
            generalStatusMessage = "Loading OpenAI API usage…"
        }

        let window = Self.queryWindow(now: nowProvider(), calendar: calendar)
        let refreshedAt = nowProvider()

        async let costsOutcome = operationResult { [self] in
            try await self.client.readCosts(
                adminKey: adminKey,
                startTime: window.startTime,
                endTime: window.endTime,
                limit: window.limit
            )
        }

        async let usageOutcome = operationResult { [self] in
            try await self.client.readCompletionsUsage(
                adminKey: adminKey,
                startTime: window.startTime,
                endTime: window.endTime,
                limit: window.limit
            )
        }

        let (costsResult, usageResult) = await (costsOutcome, usageOutcome)
        applyRefreshResults(
            costsResult: costsResult,
            usageResult: usageResult,
            refreshedAt: refreshedAt
        )
    }

    func saveAdminKey(_ adminKey: String) throws {
        let trimmedKey = adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return
        }

        try adminKeyStore.writeAdminKey(trimmedKey)
        hasConfiguredAdminKey = true
        generalStatusMessage = nil
    }

    func removeAdminKey() throws {
        try adminKeyStore.removeAdminKey()
        clearForMissingAdminKey()
    }

    static func snapshot(
        fromCosts costBuckets: [OpenAICostBucket]?,
        usageBuckets: [OpenAICompletionsUsageBucket]?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OpenAIUsageSnapshot? {
        guard costBuckets != nil || usageBuckets != nil else {
            return nil
        }

        let startOfToday = calendar.startOfDay(for: now)

        return OpenAIUsageSnapshot(
            today: rollup(
                costBuckets: costBuckets?.filter { calendar.isDate($0.startDate, inSameDayAs: startOfToday) },
                usageBuckets: usageBuckets?.filter { calendar.isDate($0.startDate, inSameDayAs: startOfToday) }
            ),
            trailingThirtyDays: rollup(costBuckets: costBuckets, usageBuckets: usageBuckets)
        )
    }

    static func makePeriodSummaries(
        from snapshot: OpenAIUsageSnapshot,
        locale: Locale = .current
    ) -> [PeriodSummaryViewData] {
        [
            makePeriodSummary(title: "Today", rollup: snapshot.today, locale: locale),
            makePeriodSummary(title: "30 days", rollup: snapshot.trailingThirtyDays, locale: locale)
        ]
    }

    private func endpointStatusMessage(
        label: String,
        failureMessage: String?,
        hasCachedData: Bool
    ) -> String? {
        guard let failureMessage else {
            return nil
        }

        return hasCachedData ? "\(label) stale: \(failureMessage)" : "\(label) unavailable: \(failureMessage)"
    }

    private func applyRefreshResults(
        costsResult: FetchResult<[OpenAICostBucket]>,
        usageResult: FetchResult<[OpenAICompletionsUsageBucket]>,
        refreshedAt: Date
    ) {
        switch costsResult {
        case let .success(costBuckets):
            cachedCostBuckets = costBuckets
            costsLastUpdated = refreshedAt
            costsFailureMessage = nil
        case let .failure(message):
            costsFailureMessage = message
        }

        switch usageResult {
        case let .success(usageBuckets):
            cachedUsageBuckets = usageBuckets
            usageLastUpdated = refreshedAt
            usageFailureMessage = nil
        case let .failure(message):
            usageFailureMessage = message
        }

        isLoading = false

        let hasAnyData = cachedCostBuckets != nil || cachedUsageBuckets != nil
        if hasAnyData {
            generalStatusMessage = nil
        } else if costsFailureMessage != nil || usageFailureMessage != nil {
            generalStatusMessage = "Unable to load OpenAI API usage."
        } else {
            generalStatusMessage = "No OpenAI API usage data available."
        }
    }

    private func clearForMissingAdminKey() {
        hasConfiguredAdminKey = false
        isLoading = false
        cachedCostBuckets = nil
        cachedUsageBuckets = nil
        costsLastUpdated = nil
        usageLastUpdated = nil
        costsFailureMessage = nil
        usageFailureMessage = nil
        generalStatusMessage = Self.missingKeyMessage
    }

    nonisolated static func defaultRefreshDelayNanoseconds(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UInt64 {
        RateLimitStore.defaultRefreshDelayNanoseconds(now: now, calendar: calendar)
    }

    private static func queryWindow(now: Date, calendar: Calendar) -> QueryWindow {
        let startOfToday = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        return QueryWindow(
            startTime: Int64(startDate.timeIntervalSince1970),
            endTime: Int64(now.timeIntervalSince1970),
            limit: 30
        )
    }

    private static func rollup(
        costBuckets: [OpenAICostBucket]?,
        usageBuckets: [OpenAICompletionsUsageBucket]?
    ) -> OpenAIUsageRollup {
        let costAmount: Decimal?
        let currencyCode: String?
        if let costBuckets {
            let totals = costBuckets.flatMap(\.results)
            let knownAmounts = totals.compactMap { $0.amount?.value }
            if knownAmounts.isEmpty {
                costAmount = nil
            } else {
                costAmount = knownAmounts.reduce(into: Decimal.zero) { partialResult, value in
                    partialResult += value
                }
            }
            currencyCode = totals.compactMap { $0.amount?.currency }.first ?? "USD"
        } else {
            costAmount = nil
            currencyCode = nil
        }

        let requestCount: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        if let usageBuckets {
            let totals = usageBuckets.flatMap(\.results)
            requestCount = totals.reduce(0) { $0 + $1.numModelRequests }
            inputTokens = totals.reduce(0) { $0 + $1.inputTokens }
            outputTokens = totals.reduce(0) { $0 + $1.outputTokens }
        } else {
            requestCount = nil
            inputTokens = nil
            outputTokens = nil
        }

        return OpenAIUsageRollup(
            costAmount: costAmount,
            currencyCode: currencyCode,
            requestCount: requestCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    private static func makePeriodSummary(
        title: String,
        rollup: OpenAIUsageRollup,
        locale: Locale
    ) -> PeriodSummaryViewData {
        let primaryParts = [
            OpenAIUsageFormatter.currencyText(
                for: rollup.costAmount,
                currencyCode: rollup.currencyCode,
                locale: locale
            ).map { "\($0) spent" },
            OpenAIUsageFormatter.countText(for: rollup.requestCount, locale: locale).map { "\($0) requests" }
        ].compactMap { $0 }

        let secondaryParts = [
            OpenAIUsageFormatter.countText(for: rollup.inputTokens, locale: locale).map { "\($0) input" },
            OpenAIUsageFormatter.countText(for: rollup.outputTokens, locale: locale).map { "\($0) output" }
        ].compactMap { $0 }

        return PeriodSummaryViewData(
            title: title,
            primaryText: primaryParts.isEmpty ? nil : primaryParts.joined(separator: " · "),
            secondaryText: secondaryParts.isEmpty ? nil : secondaryParts.joined(separator: " · ")
        )
    }

    private func operationResult<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async -> FetchResult<T> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static let missingKeyMessage = "Configure an OpenAI admin key to view organization API usage."
}
