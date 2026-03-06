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

    func codexSnapshot() -> CodexRateLimitsSnapshot {
        if let codexSnapshot = rateLimitsByLimitId?["codex"] {
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

struct RateLimitRowViewData: Equatable, Sendable {
    let label: String
    let percentText: String
    let resetText: String

    init(window: CodexRateLimitWindow, now: Date = Date(), calendar: Calendar = .current) {
        label = RateLimitFormatter.windowLabel(for: window.windowDurationMins)
        percentText = "\(RateLimitFormatter.remainingPercent(fromUsedPercent: window.usedPercent))%"
        resetText = RateLimitFormatter.resetText(for: window.resetDate, now: now, calendar: calendar)
    }
}
