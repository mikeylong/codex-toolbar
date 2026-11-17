import Foundation

struct ClaudeUsageSnapshot: Equatable, Sendable {
    let windows: [ClaudeUsageWindow]
}

struct ClaudeUsageWindow: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Int
    let resetDescription: String?
}

enum ClaudeUsageError: LocalizedError, Equatable, Sendable {
    case cliNotFound
    case notAuthenticated
    case notSubscription
    case noQuotaData
    case unsupportedResponse
    case timedOut
    case outputLimitExceeded
    case commandFailed
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Claude CLI not found. Install Claude Code to view its usage."
        case .notAuthenticated:
            return "Sign in to Claude Code, then refresh Claude usage."
        case .notSubscription:
            return "Claude Code is using API billing. Sign in with a Claude subscription to view plan limits."
        case .noQuotaData:
            return "Claude returned no plan limits. Check /usage in Claude Code; older CLI versions may need an update."
        case .unsupportedResponse:
            return "Claude returned an unsupported usage response. Update Claude Code, then refresh."
        case .timedOut:
            return "Timed out reading Claude usage. Try refreshing again."
        case .outputLimitExceeded:
            return "Claude usage output exceeded the allowed size."
        case .commandFailed:
            return "Unable to read Claude usage. Check /usage in Claude Code, then refresh."
        case .launchFailed:
            return "Unable to launch the Claude usage reader."
        }
    }
}

enum ClaudeUsageParser {
    private struct Envelope: Decodable {
        let type: String?
        let local_command: String?
        let subtype: String?
        let is_error: Bool?
        let num_turns: Int?
        let duration_api_ms: Int?
        let total_cost_usd: Double?
        let result: String?
    }

    static func parse(_ data: Data) throws -> ClaudeUsageSnapshot {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ClaudeUsageError.unsupportedResponse
        }
        let report = envelope.result ?? ""
        if envelope.is_error == true {
            throw reportsAuthenticationFailure(report) ? ClaudeUsageError.notAuthenticated : .commandFailed
        }
        guard envelope.type == "result", envelope.local_command == "usage",
              envelope.subtype == "success", envelope.is_error == false,
              envelope.num_turns == 0, envelope.duration_api_ms == 0,
              envelope.total_cost_usd == 0
        else {
            throw ClaudeUsageError.unsupportedResponse
        }

        let quotaReport = report.components(separatedBy: .newlines).prefix { line in
            // The rest of /usage can contain private project insights and percentages
            // that describe activity, not subscription limits. Never parse or retain it.
            !line.trimmingCharacters(in: .whitespaces).lowercased()
                .replacingOccurrences(of: "’", with: "'").hasPrefix("what's contributing")
        }
        let expression = try NSRegularExpression(
            pattern: #"^(Current session|Current week(?: \(([^()]+)\))?):\s*([+-]?\d+(?:\.\d+)?)%\s+(used|left)(?:\s*[·•]\s*(.+))?\s*$"#,
            options: [.caseInsensitive]
        )
        var windows: [ClaudeUsageWindow] = []
        var identifiers = Set<String>()
        for rawLine in quotaReport {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            guard lower.hasPrefix("current session:") || lower.hasPrefix("current week:")
                    || lower.hasPrefix("current week (") else { continue }
            guard let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let heading = capture(1, match: match, in: line),
                  let amountText = capture(3, match: match, in: line),
                  let amount = Double(amountText), amount.isFinite, (0...100).contains(amount),
                  let direction = capture(4, match: match, in: line)
            else { throw ClaudeUsageError.unsupportedResponse }

            let scope = capture(2, match: match, in: line)?.trimmingCharacters(in: .whitespaces)
            let isSession = heading.lowercased() == "current session"
            let title = isSession ? "Session" : (scope == nil || scope?.lowercased() == "all models"
                ? "Weekly" : "Weekly (\(scope!))")
            let id = heading.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            guard identifiers.insert(id).inserted else { throw ClaudeUsageError.unsupportedResponse }
            let used = direction.lowercased() == "left" ? 100 - amount : amount
            let reset = capture(5, match: match, in: line).flatMap(normalizedReset)
            windows.append(ClaudeUsageWindow(id: id, title: title, usedPercent: Int(used.rounded()), resetDescription: reset))
        }
        guard !windows.isEmpty else {
            if reportsAuthenticationFailure(quotaReport.joined(separator: "\n")) {
                throw ClaudeUsageError.notAuthenticated
            }
            throw ClaudeUsageError.noQuotaData
        }
        return ClaudeUsageSnapshot(windows: windows)
    }

    static func reportsAuthenticationFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["not logged in", "please run /login", "please log in", "login required",
                "authentication failed", "oauth token has expired", "invalid authentication credentials"]
            .contains { lower.contains($0) }
    }

    private static func capture(_ index: Int, match: NSTextCheckingResult, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func normalizedReset(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let prefix = trimmed.range(of: #"^resets?\s+"#, options: [.regularExpression, .caseInsensitive]) {
            return "Resets " + trimmed[prefix.upperBound...]
        }
        return trimmed
    }
}
