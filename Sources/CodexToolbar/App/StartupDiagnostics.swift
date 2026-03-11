import Foundation

package struct StartupDiagnosticsConfiguration: Equatable, Sendable {
    package let outputPath: String
    package let terminateAfterFirstReport: Bool

    package static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StartupDiagnosticsConfiguration? {
        let outputPath = argumentValue(named: "--startup-diagnostics-output", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_OUTPUT"]
            ?? environment["QUOTABAR_STARTUP_DIAGNOSTICS_OUTPUT"]

        guard let outputPath, !outputPath.isEmpty else {
            return nil
        }

        let terminateAfterFirstReport = boolValue(
            argumentValue(named: "--startup-diagnostics-exit", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_EXIT"]
                ?? environment["QUOTABAR_STARTUP_DIAGNOSTICS_EXIT"],
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

package struct StartupDiagnosticsRecord: Codable, Equatable, Sendable {
    package let launched: Bool
    package let state: String
    package let statusMessage: String
    package let debugDetail: String?
    package let cardCount: Int
    package let statusBarText: String
    package let loginItemStatus: String
    package let timestamp: String

    @MainActor
    package init(store: RateLimitStore, loginItemStatus: String, timestamp: Date = Date()) {
        launched = true
        state = Self.stateString(for: store.state)
        statusMessage = store.statusMessage
        debugDetail = store.debugDetail
        cardCount = store.cards.count
        statusBarText = store.statusBarText
        self.loginItemStatus = loginItemStatus
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
    }

    package func isValidFirstRunState(validErrorMessages: Set<String>) -> Bool {
        switch state {
        case "ready":
            return cardCount > 0
        case "error":
            return validErrorMessages.contains(statusMessage)
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
package final class StartupDiagnosticsReporter {
    private let configuration: StartupDiagnosticsConfiguration

    package init(configuration: StartupDiagnosticsConfiguration) {
        self.configuration = configuration
    }

    package func report(store: RateLimitStore, loginItemStatus: String) throws {
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
