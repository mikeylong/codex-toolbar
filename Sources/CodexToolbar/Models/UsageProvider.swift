enum UsageProvider: String, CaseIterable, Sendable {
    case codex
    case claude

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

enum UsageProviderSelection: String, CaseIterable, Sendable {
    case codex
    case claude
    case both

    var providers: [UsageProvider] {
        switch self {
        case .codex: [.codex]
        case .claude: [.claude]
        case .both: [.codex, .claude]
        }
    }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .both: "Both"
        }
    }
}
