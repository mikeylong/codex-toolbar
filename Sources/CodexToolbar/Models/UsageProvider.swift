import Foundation

enum UsageProvider: String, CaseIterable, Sendable {
    case codex
    case claude

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var usageURL: URL {
        switch self {
        case .codex: URL(string: "https://chatgpt.com/settings/usage")!
        case .claude: URL(string: "https://claude.ai/settings/usage")!
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
