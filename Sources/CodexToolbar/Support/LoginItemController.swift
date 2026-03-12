import Foundation
import Observation
import ServiceManagement

enum LoginItemRegistrationStatus: Equatable {
    case enabled
    case requiresApproval
    case notFound
    case notRegistered
    case unavailable
}

@MainActor
protocol LoginItemService {
    var status: LoginItemRegistrationStatus { get }
    func register() throws
    func unregister() throws
}

struct MainAppLoginItemService: LoginItemService {
    var status: LoginItemRegistrationStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            return .notRegistered
        @unknown default:
            return .unavailable
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

enum LoginItemControllerError: LocalizedError, Equatable {
    case unregisterFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unregisterFailed(message):
            return message
        }
    }
}

@MainActor
@Observable
final class LoginItemController {
    static let shared = LoginItemController()

    var isEnabled = false
    var statusMessage = ""
    private(set) var registrationStatus: LoginItemRegistrationStatus = .unavailable
    private let service: any LoginItemService

    init(service: any LoginItemService = MainAppLoginItemService()) {
        self.service = service
        reload()
    }

    func reload() {
        registrationStatus = service.status

        switch registrationStatus {
        case .enabled:
            isEnabled = true
            statusMessage = "Launch at login enabled"
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Requires approval in Login Items"
        case .notFound:
            isEnabled = false
            statusMessage = "Install / launch the app bundle to enable launch at login"
        case .notRegistered:
            isEnabled = false
            statusMessage = "Launch at login disabled"
        case .unavailable:
            isEnabled = false
            statusMessage = "Launch at login unavailable"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        reload()
    }

    func unregisterForMaintenance() throws {
        reload()

        switch registrationStatus {
        case .enabled, .requiresApproval:
            try service.unregister()
            reload()
        case .notFound, .notRegistered:
            reload()
        case .unavailable:
            throw LoginItemControllerError.unregisterFailed(statusMessage)
        }

        guard registrationStatus == .notFound || registrationStatus == .notRegistered else {
            throw LoginItemControllerError.unregisterFailed(statusMessage)
        }
    }
}
