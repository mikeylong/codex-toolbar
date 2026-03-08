import Foundation

struct StartupDiagnosticsConfiguration: Equatable, Sendable {
    let outputPath: String
    let terminateAfterFirstReport: Bool

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StartupDiagnosticsConfiguration? {
        let outputPath = argumentValue(named: "--startup-diagnostics-output", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_OUTPUT"]

        guard let outputPath, !outputPath.isEmpty else {
            return nil
        }

        let terminateAfterFirstReport = boolValue(
            argumentValue(named: "--startup-diagnostics-exit", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_EXIT"],
            defaultValue: false
        )

        return StartupDiagnosticsConfiguration(
            outputPath: outputPath,
            terminateAfterFirstReport: terminateAfterFirstReport
        )
    }

    private static func argumentValue(named flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    private static func boolValue(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value else {
            return defaultValue
        }

        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }
}

struct StartupDiagnosticsRecord: Codable, Equatable, Sendable {
    let launched: Bool
    let state: String
    let statusMessage: String
    let cardCount: Int
    let statusBarText: String
    let loginItemStatus: String
    let timestamp: String

    @MainActor
    init(store: RateLimitStore, loginItemStatus: String, timestamp: Date = Date()) {
        launched = true
        state = Self.stateString(for: store.state)
        statusMessage = store.statusMessage
        cardCount = store.cards.count
        statusBarText = store.statusBarText
        self.loginItemStatus = loginItemStatus
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
    }

    var isValidFirstRunState: Bool {
        switch state {
        case "ready":
            return cardCount > 0
        case "error":
            return statusMessage == "Codex CLI not found."
                || statusMessage == "Sign in to Codex to view rate limits."
                || statusMessage == "No rate-limit data available."
        default:
            return false
        }
    }

    private static func stateString(for state: RateLimitStore.State) -> String {
        switch state {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .ready:
            return "ready"
        case .error:
            return "error"
        }
    }
}

@MainActor
final class StartupDiagnosticsReporter {
    private let configuration: StartupDiagnosticsConfiguration

    init(configuration: StartupDiagnosticsConfiguration) {
        self.configuration = configuration
    }

    func report(store: RateLimitStore, loginItemStatus: String) throws {
        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: loginItemStatus)
        let data = try JSONEncoder.prettyPrinted.encode(record)
        let url = URL(fileURLWithPath: configuration.outputPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
