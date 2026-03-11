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

struct RateLimitCardViewData: Equatable, Sendable {
    let title: String
    let compactLabel: String
    let usedPercent: Int
    let remainingPercent: Int
    let usageText: String
    let relativeResetText: String?
    let absoluteResetText: String
    let combinedResetText: String
    let progressState: RateLimitProgressState
    let isPrimary: Bool
    let statusMessage: String?
    let resetDate: Date?

    var accessibilityLabel: String {
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

    init(
        window: CodexRateLimitWindow,
        displayWindowDurationMins: Int? = nil,
        isPrimary: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let displayDurationMins = displayWindowDurationMins ?? window.windowDurationMins

        title = RateLimitFormatter.windowTitle(for: displayDurationMins)
        compactLabel = RateLimitFormatter.compactWindowLabel(for: displayDurationMins)
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
