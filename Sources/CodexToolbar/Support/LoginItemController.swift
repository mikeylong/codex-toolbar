import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemController {
    static let shared = LoginItemController()

    var isEnabled = false
    var statusMessage = ""

    private init() {
        reload()
    }

    func reload() {
        let status = SMAppService.mainApp.status

        switch status {
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
        @unknown default:
            isEnabled = false
            statusMessage = "Launch at login unavailable"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        reload()
    }
}
