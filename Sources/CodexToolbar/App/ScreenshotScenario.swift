import AppKit
import Foundation

package enum ScreenshotAppearance: String, CaseIterable, Equatable, Sendable {
    case light
    case dark

    package var appAppearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

package struct ScreenshotScenario: Equatable, Sendable {
    package let name: String
    package let snapshot: CodexRateLimitsSnapshot
    package let now: Date
    package let lastUpdated: Date
    package let calendar: Calendar
    package let locale: Locale
    package let timeZone: TimeZone

    package static func named(_ name: String) -> ScreenshotScenario? {
        switch name.lowercased() {
        case "normal":
            return normal
        case "warning":
            return warning
        case "critical":
            return critical
        case "exhausted":
            return exhausted
        case "multiweek":
            return multiweek
        default:
            return nil
        }
    }

    private static let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacificTimeZone
        return calendar
    }()

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: pacificTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private static func snapshot(
        primaryUsed: Int,
        primaryReset: Date,
        secondaryUsed: Int,
        secondaryReset: Date,
        secondaryDurationMinutes: Int = 10080
    ) -> CodexRateLimitsSnapshot {
        CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex",
            limitName: "Codex",
            planType: .pro,
            primary: CodexRateLimitWindow(
                resetsAt: Int64(primaryReset.timeIntervalSince1970),
                usedPercent: primaryUsed,
                windowDurationMins: 300
            ),
            secondary: CodexRateLimitWindow(
                resetsAt: Int64(secondaryReset.timeIntervalSince1970),
                usedPercent: secondaryUsed,
                windowDurationMins: secondaryDurationMinutes
            )
        )
    }

    package static let normal: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 13, minute: 3)
        let primaryReset = date(year: 2026, month: 3, day: 8, hour: 13, minute: 54)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "normal",
            snapshot: snapshot(primaryUsed: 19, primaryReset: primaryReset, secondaryUsed: 10, secondaryReset: secondaryReset),
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    package static let warning: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 14, minute: 11)
        let primaryReset = date(year: 2026, month: 3, day: 8, hour: 14, minute: 46)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "warning",
            snapshot: snapshot(primaryUsed: 74, primaryReset: primaryReset, secondaryUsed: 41, secondaryReset: secondaryReset),
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    package static let critical: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 16, minute: 22)
        let primaryReset = date(year: 2026, month: 3, day: 8, hour: 16, minute: 31)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "critical",
            snapshot: snapshot(primaryUsed: 94, primaryReset: primaryReset, secondaryUsed: 84, secondaryReset: secondaryReset),
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    package static let exhausted: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 18, minute: 5)
        let primaryReset = date(year: 2026, month: 3, day: 8, hour: 18, minute: 5)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "exhausted",
            snapshot: snapshot(primaryUsed: 100, primaryReset: primaryReset, secondaryUsed: 91, secondaryReset: secondaryReset),
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    package static let multiweek: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 10, hour: 22, minute: 46)
        let primaryReset = date(year: 2026, month: 3, day: 10, hour: 23, minute: 7)
        let secondaryReset = date(year: 2026, month: 3, day: 17, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "multiweek",
            snapshot: snapshot(
                primaryUsed: 15,
                primaryReset: primaryReset,
                secondaryUsed: 99,
                secondaryReset: secondaryReset,
                secondaryDurationMinutes: 10081
            ),
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()
}

package struct ScreenshotLaunchConfiguration: Equatable, Sendable {
    package let scenario: ScreenshotScenario
    package let appearance: ScreenshotAppearance
    package let outputDirectory: String?
    package let shouldCapturePopover: Bool
    package let shouldCaptureStatusItem: Bool
    package let shouldOpenPopover: Bool

    package static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ScreenshotLaunchConfiguration? {
        let scenarioName = argumentValue(named: "--screenshot-scenario", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_SCREENSHOT_SCENARIO"]
            ?? environment["QUOTABAR_SCREENSHOT_SCENARIO"]

        guard let scenarioName, let scenario = ScreenshotScenario.named(scenarioName) else {
            return nil
        }

        let appearanceName = argumentValue(named: "--screenshot-appearance", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_SCREENSHOT_APPEARANCE"]
            ?? environment["QUOTABAR_SCREENSHOT_APPEARANCE"]
            ?? ScreenshotAppearance.light.rawValue
        let appearance = ScreenshotAppearance(rawValue: appearanceName.lowercased()) ?? .light

        let outputDirectory = argumentValue(named: "--screenshot-output-dir", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_SCREENSHOT_OUTPUT_DIR"]
            ?? environment["QUOTABAR_SCREENSHOT_OUTPUT_DIR"]
        let shouldCapturePopover = boolValue(
            argumentValue(named: "--screenshot-capture-popover", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_CAPTURE_POPOVER"]
                ?? environment["QUOTABAR_SCREENSHOT_CAPTURE_POPOVER"],
            defaultValue: true
        )
        let shouldCaptureStatusItem = boolValue(
            argumentValue(named: "--screenshot-capture-status-item", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_CAPTURE_STATUS_ITEM"]
                ?? environment["QUOTABAR_SCREENSHOT_CAPTURE_STATUS_ITEM"],
            defaultValue: false
        )
        let shouldOpenPopover = boolValue(
            argumentValue(named: "--screenshot-open-popover", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_OPEN_POPOVER"]
                ?? environment["QUOTABAR_SCREENSHOT_OPEN_POPOVER"],
            defaultValue: shouldCapturePopover
        )

        return ScreenshotLaunchConfiguration(
            scenario: scenario,
            appearance: appearance,
            outputDirectory: outputDirectory,
            shouldCapturePopover: shouldCapturePopover,
            shouldCaptureStatusItem: shouldCaptureStatusItem,
            shouldOpenPopover: shouldOpenPopover
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
