import XCTest
@testable import CodexToolbar

@MainActor
final class MaintenanceLaunchTests: XCTestCase {
    func testMaintenanceLaunchConfigurationReadsArguments() {
        let configuration = MaintenanceLaunchConfiguration.current(
            arguments: ["CodexToolbar", "--maintenance-action", "unregister-login-item"],
            environment: [:]
        )

        XCTAssertEqual(configuration, MaintenanceLaunchConfiguration(action: .unregisterLoginItem))
    }

    func testMaintenanceLaunchConfigurationReadsEnvironmentFallback() {
        let configuration = MaintenanceLaunchConfiguration.current(
            arguments: ["CodexToolbar"],
            environment: ["CODEX_TOOLBAR_MAINTENANCE_ACTION": "unregister-login-item"]
        )

        XCTAssertEqual(configuration, MaintenanceLaunchConfiguration(action: .unregisterLoginItem))
    }

    func testMaintenanceRunnerSucceedsWhenUnregisterDisablesLaunchAtLogin() {
        let service = FakeLoginItemService()
        service.currentStatus = .enabled
        service.nextUnregisterStatus = .notRegistered
        let controller = LoginItemController(service: service)

        let result = MaintenanceActionRunner(loginItemController: controller)
            .run(configuration: MaintenanceLaunchConfiguration(action: .unregisterLoginItem))

        XCTAssertEqual(result, .success("Launch at login unregistered."))
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.registrationStatus, .notRegistered)
    }

    func testMaintenanceRunnerFailsWhenUnregisterLeavesLaunchAtLoginEnabled() {
        let service = FakeLoginItemService()
        service.currentStatus = .enabled
        service.nextUnregisterStatus = .enabled
        let controller = LoginItemController(service: service)

        let result = MaintenanceActionRunner(loginItemController: controller)
            .run(configuration: MaintenanceLaunchConfiguration(action: .unregisterLoginItem))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.registrationStatus, .enabled)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var currentStatus: LoginItemRegistrationStatus = .notRegistered
    var nextRegisterStatus: LoginItemRegistrationStatus = .enabled
    var nextUnregisterStatus: LoginItemRegistrationStatus = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    var status: LoginItemRegistrationStatus {
        currentStatus
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        currentStatus = nextRegisterStatus
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        currentStatus = nextUnregisterStatus
    }
}
