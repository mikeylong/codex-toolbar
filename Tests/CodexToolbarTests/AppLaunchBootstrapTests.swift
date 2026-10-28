import Foundation
import XCTest
@testable import CodexToolbar

final class AppLaunchBootstrapTests: XCTestCase {
    private let bundleURL = URL(fileURLWithPath: "/Applications/Codex Toolbar.app")

    func testFirstUIProcessAlwaysHandsOffBeforeCreatingApplication() throws {
        // Even an orphaned shell launch can have launchd as its current parent.
        // Do not treat parent PID 1 alone as proof of a LaunchServices launch.
        for parentID: Int32 in [1, 42] {
            let plan = try makePlan(parentID: parentID)
            XCTAssertEqual(plan, .openBundle(arguments: [
                "-n", "-g", bundleURL.path, "--args", AppLaunchBootstrap.handoffArgument
            ]))
        }
    }

    func testLaunchServicesChildRunsWithoutAnotherHandoff() throws {
        XCTAssertEqual(
            try makePlan(parentID: 1, arguments: ["CodexToolbar", AppLaunchBootstrap.handoffArgument]),
            .runApplication
        )
    }

    func testDirectInvocationCannotUseHandoffArgumentToRunUnderHost() {
        XCTAssertThrowsError(try makePlan(
            arguments: ["CodexToolbar", AppLaunchBootstrap.handoffArgument]
        ))
    }

    func testScreenshotHandoffWaitsAndPreservesArgumentsAndExplicitEnvironment() throws {
        let arguments = ["CodexToolbar", "--screenshot-scenario", "normal"]
        let environment = [
            "CODEX_TOOLBAR_SCREENSHOT_OUTPUT_DIR": "/tmp/Toolbar captures",
            "PATH": "/custom/bin:/usr/bin",
            "__CFBundleIdentifier": "com.openai.codex",
            "DYLD_INSERT_LIBRARIES": "/tmp/injected.dylib",
            "UNRELATED_SECRET": "do not forward"
        ]
        XCTAssertEqual(try makePlan(arguments: arguments, environment: environment), .openBundle(arguments: [
            "-n", "-g", "-W",
            "--env", "CODEX_TOOLBAR_SCREENSHOT_OUTPUT_DIR=/tmp/Toolbar captures",
            "--env", "PATH=/custom/bin:/usr/bin",
            bundleURL.path, "--args", AppLaunchBootstrap.handoffArgument,
            "--screenshot-scenario", "normal"
        ]))
    }

    func testTerminatingDiagnosticsHandoffWaits() throws {
        guard case let .openBundle(arguments) = try makePlan(environment: [
            "CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_OUTPUT": "/tmp/startup.json",
            "CODEX_TOOLBAR_STARTUP_DIAGNOSTICS_EXIT": "true"
        ]) else { return XCTFail("Expected a LaunchServices handoff") }
        XCTAssertTrue(arguments.contains("-W"))
    }

    func testMaintenanceCommandRunsInPlaceWithoutUIHandoff() throws {
        XCTAssertEqual(try makePlan(arguments: [
            "CodexToolbar", "--maintenance-action", "unregister-login-item"
        ]), .runApplication)
        XCTAssertEqual(try makePlan(environment: [
            "CODEX_TOOLBAR_MAINTENANCE_ACTION": "unregister-login-item"
        ]), .runApplication)
    }

    func testBareSwiftExecutableIsRejectedBeforeCreatingUI() {
        XCTAssertThrowsError(try AppLaunchBootstrap.plan(
            bundleURL: URL(fileURLWithPath: "/repo/.build/debug"),
            bundleIdentifier: nil,
            operatingSystemMajorVersion: 27,
            parentProcessID: 42,
            arguments: ["CodexToolbar"],
            environment: [:]
        ))
    }

    func testOlderMacOSKeepsExistingBundledLaunchBehavior() throws {
        XCTAssertEqual(try AppLaunchBootstrap.plan(
            bundleURL: bundleURL,
            bundleIdentifier: "com.mikelong.codextoolbar",
            operatingSystemMajorVersion: 14,
            parentProcessID: 42,
            arguments: ["CodexToolbar"],
            environment: [:]
        ), .runApplication)
    }

    private func makePlan(
        parentID: Int32 = 42,
        arguments: [String] = ["CodexToolbar"],
        environment: [String: String] = [:]
    ) throws -> AppLaunchPlan {
        try AppLaunchBootstrap.plan(
            bundleURL: bundleURL,
            bundleIdentifier: "com.mikelong.codextoolbar",
            operatingSystemMajorVersion: 27,
            parentProcessID: parentID,
            arguments: arguments,
            environment: environment
        )
    }
}
