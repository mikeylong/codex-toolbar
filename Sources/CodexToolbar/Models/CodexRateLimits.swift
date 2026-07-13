import Foundation

enum PlanType: String, Codable, Sendable {
    case free
    case go
    case plus
    case pro
    case team
    case business
    case enterprise
    case edu
    case unknown
}

struct CreditsSnapshot: Codable, Equatable, Sendable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool
}

struct CodexRateLimitWindow: Codable, Equatable, Sendable {
    let resetsAt: Int64?
    let usedPercent: Int
    let windowDurationMins: Int?

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }
}

struct CodexRateLimitsSnapshot: Codable, Equatable, Sendable {
    let credits: CreditsSnapshot?
    let limitId: String?
    let limitName: String?
    let planType: PlanType?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

struct GetAccountRateLimitsResponse: Codable, Equatable, Sendable {
    let rateLimits: CodexRateLimitsSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitsSnapshot]?

    func displaySnapshot() -> CodexRateLimitsSnapshot {
        if rateLimits.primary != nil || rateLimits.secondary != nil {
            return rateLimits
        }

        if let codexSnapshot = rateLimitsByLimitId?["codex"],
           codexSnapshot.primary != nil || codexSnapshot.secondary != nil
        {
            return codexSnapshot
        }

        return rateLimits
    }

    func cardCandidates(
        supplementalFamilies: [SupplementalLimitFamily] = Self.supportedSupplementalFamilies
    ) -> [RateLimitCardCandidate] {
        let primarySnapshot = displaySnapshot()
        let primaryLimitId = primarySnapshot.limitId ?? Self.codexLimitId
        var candidates: [RateLimitCardCandidate] = [
            RateLimitCardCandidate(
                limitId: primaryLimitId,
                limitName: primarySnapshot.limitName,
                categoryLabel: nil,
                snapshot: primarySnapshot
            )
        ]

        for family in supplementalFamilies {
            guard let snapshot = rateLimitsByLimitId?[family.limitId],
                  (snapshot.primary != nil || snapshot.secondary != nil),
                  family.limitId != primaryLimitId
            else {
                continue
            }

            candidates.append(
                RateLimitCardCandidate(
                    limitId: family.limitId,
                    limitName: snapshot.limitName,
                    categoryLabel: family.categoryLabel,
                    snapshot: snapshot
                )
            )
        }

        return candidates
    }

    static let codexLimitId = "codex"
    static let supportedSupplementalFamilies: [SupplementalLimitFamily] = [
        SupplementalLimitFamily(
            limitId: "codex_bengalfox",
            categoryLabel: "GPT-5.3-Codex-Spark",
            sortOrder: 1,
            isUserToggleable: true
        )
    ]

    static func supplementalFamily(for limitId: String) -> SupplementalLimitFamily? {
        supportedSupplementalFamilies.first { $0.limitId == limitId }
    }
}

struct SupplementalLimitFamily: Equatable, Sendable {
    let limitId: String
    let categoryLabel: String
    let sortOrder: Int
    let isUserToggleable: Bool
}

struct RateLimitCardCandidate: Equatable, Sendable {
    let limitId: String
    let limitName: String?
    let categoryLabel: String?
    let snapshot: CodexRateLimitsSnapshot
}

struct RateLimitCardSectionViewData: Equatable, Sendable {
    let familyId: String
    let title: String?
    let cards: [RateLimitCardViewData]
    let isGrouped: Bool
    let showsTitle: Bool
}

struct GetAccountResponse: Codable, Equatable, Sendable {
    let account: Account?
    let requiresOpenaiAuth: Bool
}

enum Account: Codable, Equatable, Sendable {
    case apiKey
    case chatgpt(email: String, planType: PlanType)

    enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    enum AccountType: String, Codable {
        case apiKey
        case chatgpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AccountType.self, forKey: .type) {
        case .apiKey:
            self = .apiKey
        case .chatgpt:
            self = .chatgpt(
                email: try container.decode(String.self, forKey: .email),
                planType: try container.decode(PlanType.self, forKey: .planType)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apiKey:
            try container.encode(AccountType.apiKey, forKey: .type)
        case let .chatgpt(email, planType):
            try container.encode(AccountType.chatgpt, forKey: .type)
            try container.encode(email, forKey: .email)
            try container.encode(planType, forKey: .planType)
        }
    }
}

enum RateLimitProgressState: Equatable, Sendable {
    case normal
    case warning
    case critical
    case exhausted

    init(remainingPercent: Int) {
        switch remainingPercent {
        case ...0:
            self = .exhausted
        case 1...10:
            self = .critical
        case 11...30:
            self = .warning
        default:
            self = .normal
        }
    }
}

enum RateLimitProjectionGraphElement: Equatable, Sendable {
    case pace
    case current
    case currentAndProjectedEmpty
    case reset
    case projectedEmpty
}

struct RateLimitProjectionViewData: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case resetFirst
        case warning
        case critical
    }

    let state: State
    let windowStartDate: Date
    let currentDate: Date
    let resetDate: Date
    let projectedEmptyDate: Date
    let currentRemainingPercent: Int
    let dailyUsePercent: Double
    let currentPosition: Double
    let resetPosition: Double
    let projectedEmptyPosition: Double
    let summaryText: String
    let detailText: String
    let paceTooltipText: String
    let currentTooltipText: String
    let resetTooltipText: String
    let projectedEmptyTooltipText: String
    let accessibilityLabel: String

    init?(
        windowLabel: String,
        window: CodexRateLimitWindow,
        remainingPercent: Int,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        guard let resetDate = window.resetDate,
              let windowDurationMins = window.windowDurationMins,
              windowDurationMins > 0,
              window.usedPercent > 0
        else {
            return nil
        }

        let windowDurationSeconds = TimeInterval(windowDurationMins) * 60
        let windowStartDate = resetDate.addingTimeInterval(-windowDurationSeconds)
        let elapsedSeconds = now.timeIntervalSince(windowStartDate)
        guard elapsedSeconds > 0 else {
            return nil
        }

        let elapsedDays = elapsedSeconds / 86_400
        let dailyUsePercent = Double(window.usedPercent) / elapsedDays
        guard dailyUsePercent > 0, dailyUsePercent.isFinite else {
            return nil
        }

        let projectedEmptyDate: Date
        if remainingPercent <= 0 {
            projectedEmptyDate = now
        } else {
            let daysUntilEmpty = Double(remainingPercent) / dailyUsePercent
            guard daysUntilEmpty.isFinite else {
                return nil
            }
            projectedEmptyDate = now.addingTimeInterval(daysUntilEmpty * 86_400)
        }

        let chartEndDate = max(resetDate, projectedEmptyDate)
        let chartDurationSeconds = chartEndDate.timeIntervalSince(windowStartDate)
        guard chartDurationSeconds > 0 else {
            return nil
        }

        let runsOutBeforeReset = projectedEmptyDate < resetDate
        let secondsUntilEmpty = projectedEmptyDate.timeIntervalSince(now)
        let state: State
        if runsOutBeforeReset {
            state = secondsUntilEmpty <= 86_400 ? .critical : .warning
        } else {
            state = .resetFirst
        }

        let projectedText = RateLimitFormatter.absoluteResetText(
            for: projectedEmptyDate,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let resetText = RateLimitFormatter.absoluteResetText(
            for: resetDate,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let paceTooltipText = Self.paceTooltipText(
            dailyUsePercent: dailyUsePercent,
            windowDurationMins: windowDurationMins,
            locale: locale
        )
        let summaryText = runsOutBeforeReset ? "Projected empty before reset" : "Reset comes first"
        let detailText = runsOutBeforeReset
            ? "Empty \(projectedText) at pace"
            : "On pace to last through reset"

        self.state = state
        self.windowStartDate = windowStartDate
        currentDate = now
        self.resetDate = resetDate
        self.projectedEmptyDate = projectedEmptyDate
        currentRemainingPercent = remainingPercent
        self.dailyUsePercent = dailyUsePercent
        currentPosition = Self.clampedPosition(for: now, start: windowStartDate, durationSeconds: chartDurationSeconds)
        resetPosition = Self.clampedPosition(for: resetDate, start: windowStartDate, durationSeconds: chartDurationSeconds)
        projectedEmptyPosition = Self.clampedPosition(for: projectedEmptyDate, start: windowStartDate, durationSeconds: chartDurationSeconds)
        self.summaryText = summaryText
        self.detailText = detailText
        self.paceTooltipText = paceTooltipText
        currentTooltipText = "Now · \(remainingPercent)% remaining"
        resetTooltipText = "Reset · \(resetText)"
        projectedEmptyTooltipText = "Projected empty · \(projectedText) at current pace"
        accessibilityLabel = "\(windowLabel) pace. \(paceTooltipText). \(summaryText). \(detailText). \(remainingPercent)% remaining."
    }

    func tooltipText(for element: RateLimitProjectionGraphElement) -> String {
        switch element {
        case .pace:
            return paceTooltipText
        case .current:
            return currentTooltipText
        case .currentAndProjectedEmpty:
            return "Now · \(currentRemainingPercent)% remaining · projected empty"
        case .reset:
            return resetTooltipText
        case .projectedEmpty:
            return projectedEmptyTooltipText
        }
    }

    private static func clampedPosition(for date: Date, start: Date, durationSeconds: TimeInterval) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }

        return min(max(date.timeIntervalSince(start) / durationSeconds, 0), 1)
    }

    private static func paceTooltipText(
        dailyUsePercent: Double,
        windowDurationMins: Int,
        locale: Locale
    ) -> String {
        let usesHourlyPace = windowDurationMins < 1_440
        let value = usesHourlyPace ? dailyUsePercent / 24 : dailyUsePercent
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value < 1 ? 2 : 1
        let formattedValue = formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
        let unit = usesHourlyPace ? "hour" : "day"
        return "Current pace · \(formattedValue)% used per \(unit)"
    }
}

struct RateLimitCardViewData: Equatable, Sendable {
    let title: String
    let compactLabel: String
    let windowDurationMins: Int?
    let usedPercent: Int
    let remainingPercent: Int
    let usageText: String
    let relativeResetText: String?
    let absoluteResetText: String
    let combinedResetText: String
    let progressState: RateLimitProgressState
    let isPrimary: Bool
    let familyId: String
    let categoryLabel: String?
    let statusMessage: String?
    let resetDate: Date?
    let projection: RateLimitProjectionViewData?

    var accessibilityLabel: String {
        var parts = [
            displayTitle,
            "\(usedPercent)% used",
            "\(remainingPercent)% remaining",
            combinedResetText
        ]

        if let statusMessage {
            parts.insert(statusMessage, at: 1)
        }

        if let projection {
            parts.append(projection.paceTooltipText)
            parts.append(projection.summaryText)
            parts.append(projection.detailText)
        }

        return parts.joined(separator: ". ")
    }

    var displayTitle: String {
        guard let categoryLabel else {
            return title
        }
        return "\(categoryLabel) · \(title)"
    }

    var familyTitle: String {
        categoryLabel ?? "Codex"
    }

    func popoverTitle(isGroupedByFamily: Bool) -> String {
        isGroupedByFamily ? title : displayTitle
    }

    init(
        window: CodexRateLimitWindow,
        displayLabelOverride: String? = nil,
        familyId: String = GetAccountRateLimitsResponse.codexLimitId,
        categoryLabel: String? = nil,
        isPrimary: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        if let displayLabelOverride {
            title = displayLabelOverride
            compactLabel = displayLabelOverride
        } else {
            title = RateLimitFormatter.windowTitle(for: window.windowDurationMins)
            compactLabel = RateLimitFormatter.compactWindowLabel(for: window.windowDurationMins)
        }
        windowDurationMins = window.windowDurationMins
        self.familyId = familyId
        self.categoryLabel = categoryLabel
        usedPercent = window.usedPercent
        remainingPercent = RateLimitFormatter.remainingPercent(fromUsedPercent: window.usedPercent)
        usageText = "\(usedPercent)% used · \(remainingPercent)% remaining"
        relativeResetText = RateLimitFormatter.relativeResetText(for: window.resetDate, now: now, calendar: calendar)
        absoluteResetText = RateLimitFormatter.absoluteResetText(
            for: window.resetDate,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        combinedResetText = RateLimitFormatter.combinedResetText(
            for: window.resetDate,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        progressState = RateLimitProgressState(remainingPercent: remainingPercent)
        self.isPrimary = isPrimary
        resetDate = window.resetDate
        let normalizedDuration = window.windowDurationMins.map(RateLimitFormatter.normalizedWindowMinutes)
        if familyId == GetAccountRateLimitsResponse.codexLimitId,
           normalizedDuration == 300 || normalizedDuration == 10_080
        {
            projection = RateLimitProjectionViewData(
                windowLabel: title,
                window: window,
                remainingPercent: remainingPercent,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        } else {
            projection = nil
        }

        switch progressState {
        case .normal:
            statusMessage = nil
        case .warning:
            statusMessage = "Approaching limit"
        case .critical:
            statusMessage = "Very little capacity remaining"
        case .exhausted:
            statusMessage = "Rate limit reached"
        }
    }
}
