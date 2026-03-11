import Foundation

package enum PlanType: String, Codable, Sendable {
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

package struct CreditsSnapshot: Codable, Equatable, Sendable {
    package let balance: String?
    package let hasCredits: Bool
    package let unlimited: Bool

    package init(balance: String?, hasCredits: Bool, unlimited: Bool) {
        self.balance = balance
        self.hasCredits = hasCredits
        self.unlimited = unlimited
    }
}

package struct CodexRateLimitWindow: Codable, Equatable, Sendable {
    package let resetsAt: Int64?
    package let usedPercent: Int
    package let windowDurationMins: Int?

    package init(resetsAt: Int64?, usedPercent: Int, windowDurationMins: Int?) {
        self.resetsAt = resetsAt
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
    }

    package var resetDate: Date? {
        guard let resetsAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }
}

package struct CodexRateLimitsSnapshot: Codable, Equatable, Sendable {
    package let credits: CreditsSnapshot?
    package let limitId: String?
    package let limitName: String?
    package let planType: PlanType?
    package let primary: CodexRateLimitWindow?
    package let secondary: CodexRateLimitWindow?

    package init(
        credits: CreditsSnapshot?,
        limitId: String?,
        limitName: String?,
        planType: PlanType?,
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?
    ) {
        self.credits = credits
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }
}

package struct GetAccountRateLimitsResponse: Codable, Equatable, Sendable {
    package let rateLimits: CodexRateLimitsSnapshot
    package let rateLimitsByLimitId: [String: CodexRateLimitsSnapshot]?

    package init(rateLimits: CodexRateLimitsSnapshot, rateLimitsByLimitId: [String: CodexRateLimitsSnapshot]?) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }

    package func displaySnapshot() -> CodexRateLimitsSnapshot {
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
}

package struct GetAccountResponse: Codable, Equatable, Sendable {
    package let account: Account?
    package let requiresOpenaiAuth: Bool

    package init(account: Account?, requiresOpenaiAuth: Bool) {
        self.account = account
        self.requiresOpenaiAuth = requiresOpenaiAuth
    }
}

package enum Account: Codable, Equatable, Sendable {
    case apiKey
    case chatgpt(email: String, planType: PlanType)

    package enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    package enum AccountType: String, Codable {
        case apiKey
        case chatgpt
    }

    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
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

package enum RateLimitProgressState: Equatable, Sendable {
    case normal
    case warning
    case critical
    case exhausted

    package init(remainingPercent: Int) {
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

package struct RateLimitCardViewData: Equatable, Sendable {
    package let title: String
    package let compactLabel: String
    package let usedPercent: Int
    package let remainingPercent: Int
    package let usageText: String
    package let relativeResetText: String?
    package let absoluteResetText: String
    package let combinedResetText: String
    package let progressState: RateLimitProgressState
    package let isPrimary: Bool
    package let statusMessage: String?
    package let resetDate: Date?

    package var accessibilityLabel: String {
        var parts = [
            title,
            "\(usedPercent)% used",
            "\(remainingPercent)% remaining",
            combinedResetText
        ]

        if let statusMessage {
            parts.insert(statusMessage, at: 1)
        }

        return parts.joined(separator: ". ")
    }

    package init(
        window: CodexRateLimitWindow,
        displayLabelOverride: String? = nil,
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
