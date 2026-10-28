import Foundation

enum AppLaunchPlan: Equatable {
    case runApplication
    case openBundle(arguments: [String])
}

enum AppLaunchError: LocalizedError {
    case appBundleRequired
    case invalidHandoff
    case openFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .appBundleRequired:
            return "Build and launch CodexToolbar.app with ./scripts/build_app.sh and open dist/CodexToolbar.app."
        case .invalidHandoff:
            return "The UI launch must come through macOS LaunchServices. Open CodexToolbar.app."
        case let .openFailed(status):
            return "LaunchServices could not open CodexToolbar.app (exit \(status))."
        }
    }
}

enum AppLaunchBootstrap {
    // This handoff happens before SwiftUI or AppDelegate creates any UI. A raw
    // executable launch can otherwise register its status item under the host
    // app's responsible identity, even though Bundle.main has the right ID.
    static let handoffArgument = "--codex-toolbar-launch-services"

    static func plan(
        bundleURL: URL,
        bundleIdentifier: String?,
        operatingSystemMajorVersion: Int,
        parentProcessID: Int32,
        arguments: [String],
        environment: [String: String]
    ) throws -> AppLaunchPlan {
        // Maintenance commands do not create a status item and must retain
        // their synchronous command-line output and exit status.
        if MaintenanceLaunchConfiguration.current(arguments: arguments, environment: environment) != nil {
            return .runApplication
        }

        guard bundleURL.pathExtension == "app", bundleIdentifier != nil else {
            throw AppLaunchError.appBundleRequired
        }

        // Per-app menu bar ownership controls were introduced in macOS 26.
        guard operatingSystemMajorVersion >= 26 else { return .runApplication }

        if arguments.contains(handoffArgument) {
            guard parentProcessID == 1 else { throw AppLaunchError.invalidHandoff }
            return .runApplication
        }

        var openArguments = ["-n", "-g"]
        if ScreenshotLaunchConfiguration.current(arguments: arguments, environment: environment) != nil
            || StartupDiagnosticsConfiguration.current(arguments: arguments, environment: environment)?.terminateAfterFirstReport == true {
            openArguments.append("-W")
        }

        // Forward only the app's explicit launch settings and CLI search path.
        // Shell/IDE identity and injection variables belong to the launcher.
        for key in environment.keys.sorted() where key.hasPrefix("CODEX_TOOLBAR_") || key == "PATH" {
            openArguments += ["--env", "\(key)=\(environment[key]!)"]
        }
        openArguments += [bundleURL.path, "--args", handoffArgument]
        openArguments += arguments.dropFirst()
        return .openBundle(arguments: openArguments)
    }

    static func openBundle(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppLaunchError.openFailed(process.terminationStatus)
        }
    }
}
