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
