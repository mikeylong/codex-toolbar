import Foundation

enum MaintenanceAction: String, Equatable, Sendable {
    case unregisterLoginItem = "unregister-login-item"
}

struct MaintenanceLaunchConfiguration: Equatable, Sendable {
    let action: MaintenanceAction

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MaintenanceLaunchConfiguration? {
        let actionValue = argumentValue(named: "--maintenance-action", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_MAINTENANCE_ACTION"]

        guard let actionValue, let action = MaintenanceAction(rawValue: actionValue.lowercased()) else {
            return nil
        }

        return MaintenanceLaunchConfiguration(action: action)
    }

    private static func argumentValue(named flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }
}

struct MaintenanceLaunchResult: Equatable, Sendable {
    let exitCode: Int32
    let message: String

    static func success(_ message: String) -> MaintenanceLaunchResult {
        MaintenanceLaunchResult(exitCode: 0, message: message)
    }

    static func failure(_ message: String) -> MaintenanceLaunchResult {
        MaintenanceLaunchResult(exitCode: 1, message: message)
    }
}

@MainActor
struct MaintenanceActionRunner {
    let loginItemController: LoginItemController

    init(loginItemController: LoginItemController = .shared) {
        self.loginItemController = loginItemController
    }

    func run(configuration: MaintenanceLaunchConfiguration) -> MaintenanceLaunchResult {
        switch configuration.action {
        case .unregisterLoginItem:
            do {
                try loginItemController.unregisterForMaintenance()
                return .success("Launch at login unregistered.")
            } catch {
                return .failure(error.localizedDescription)
            }
        }
    }
}
