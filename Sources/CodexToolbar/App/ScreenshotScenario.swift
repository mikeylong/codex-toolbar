import AppKit
import Foundation

enum ScreenshotAppearance: String, CaseIterable, Equatable, Sendable {
    case light
    case dark

    var appAppearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

struct ScreenshotScenario: Equatable, Sendable {
    let name: String
    let snapshot: CodexRateLimitsSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitsSnapshot]?
    let now: Date
    let lastUpdated: Date
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone

    var rateLimitsResponse: GetAccountRateLimitsResponse {
        GetAccountRateLimitsResponse(
            rateLimits: snapshot,
            rateLimitsByLimitId: rateLimitsByLimitId
        )
    }

    static func named(_ name: String) -> ScreenshotScenario? {
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
        case "projection":
            return projection
        case "spark":
            return spark
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

    // Screenshot fixtures mirror the observed window structure: Codex has a
    // weekly primary window; Spark has separate 5h and weekly windows.
    private static func snapshot(
        used: Int,
        reset: Date,
        durationMinutes: Int = 10080
    ) -> CodexRateLimitsSnapshot {
        CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex",
            limitName: "Codex",
            planType: .pro,
            primary: CodexRateLimitWindow(
                resetsAt: Int64(reset.timeIntervalSince1970),
                usedPercent: used,
                windowDurationMins: durationMinutes
            ),
            secondary: nil
        )
    }

    static let normal: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 13, minute: 3)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "normal",
            snapshot: snapshot(used: 19, reset: secondaryReset),
            rateLimitsByLimitId: nil,
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    static let warning: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 14, minute: 11)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "warning",
            snapshot: snapshot(used: 74, reset: secondaryReset),
            rateLimitsByLimitId: nil,
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    static let critical: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 16, minute: 22)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "critical",
            snapshot: snapshot(used: 94, reset: secondaryReset),
            rateLimitsByLimitId: nil,
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    static let exhausted: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 8, hour: 18, minute: 5)
        let secondaryReset = date(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "exhausted",
            snapshot: snapshot(used: 100, reset: secondaryReset),
            rateLimitsByLimitId: nil,
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    static let multiweek: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 10, hour: 22, minute: 46)
        let secondaryReset = date(year: 2026, month: 3, day: 17, hour: 0, minute: 0)
        return ScreenshotScenario(
            name: "multiweek",
            snapshot: snapshot(
                used: 99,
                reset: secondaryReset,
                durationMinutes: 10081
            ),
            rateLimitsByLimitId: nil,
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    static let projection: ScreenshotScenario = {
        let now = date(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let secondaryReset = date(year: 2026, month: 5, day: 18, hour: 12, minute: 0)
        return ScreenshotScenario(
            name: "projection",
            snapshot: snapshot(used: 45, reset: secondaryReset),
            rateLimitsByLimitId: nil,
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()

    static let spark: ScreenshotScenario = {
        let now = date(year: 2026, month: 3, day: 10, hour: 10, minute: 22)
        let primaryReset = date(year: 2026, month: 3, day: 10, hour: 15, minute: 7)
        let secondaryReset = date(year: 2026, month: 3, day: 17, hour: 0, minute: 0)

        return ScreenshotScenario(
            name: "spark",
            snapshot: snapshot(used: 50, reset: secondaryReset),
            rateLimitsByLimitId: [
                "codex_bengalfox": CodexRateLimitsSnapshot(
                    credits: nil,
                    limitId: "codex_bengalfox",
                    limitName: "GPT-5.3-Codex-Spark",
                    planType: .pro,
                    primary: CodexRateLimitWindow(
                        resetsAt: Int64(primaryReset.timeIntervalSince1970),
                        usedPercent: 82,
                        windowDurationMins: 300
                    ),
                    secondary: CodexRateLimitWindow(
                        resetsAt: Int64(secondaryReset.timeIntervalSince1970) + 12_000,
                        usedPercent: 15,
                        windowDurationMins: 10_080
                    )
                )
            ],
            now: now,
            lastUpdated: now,
            calendar: calendar,
            locale: locale,
            timeZone: pacificTimeZone
        )
    }()
}

struct ScreenshotLaunchConfiguration: Equatable, Sendable {
    let scenario: ScreenshotScenario
    let appearance: ScreenshotAppearance
    let outputDirectory: String?
    let shouldCapturePopover: Bool
    let shouldCaptureStatusItem: Bool
    let shouldOpenPopover: Bool
    let visibleSupplementalFamilyIDs: Set<String>?
    let showsOpenCodexButton: Bool?

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ScreenshotLaunchConfiguration? {
        let scenarioName = argumentValue(named: "--screenshot-scenario", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_SCREENSHOT_SCENARIO"]

        guard let scenarioName, let scenario = ScreenshotScenario.named(scenarioName) else {
            return nil
        }

        let appearanceName = argumentValue(named: "--screenshot-appearance", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_SCREENSHOT_APPEARANCE"]
            ?? ScreenshotAppearance.light.rawValue
        let appearance = ScreenshotAppearance(rawValue: appearanceName.lowercased()) ?? .light

        let outputDirectory = argumentValue(named: "--screenshot-output-dir", arguments: arguments)
            ?? environment["CODEX_TOOLBAR_SCREENSHOT_OUTPUT_DIR"]
        let shouldCapturePopover = boolValue(
            argumentValue(named: "--screenshot-capture-popover", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_CAPTURE_POPOVER"],
            defaultValue: true
        )
        let shouldCaptureStatusItem = boolValue(
            argumentValue(named: "--screenshot-capture-status-item", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_CAPTURE_STATUS_ITEM"],
            defaultValue: false
        )
        let shouldOpenPopover = boolValue(
            argumentValue(named: "--screenshot-open-popover", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_OPEN_POPOVER"],
            defaultValue: shouldCapturePopover
        )
        let showsOpenCodexButton = optionalBoolValue(
            argumentValue(named: "--screenshot-show-open-codex", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_SHOW_OPEN_CODEX"]
        )
        let visibleSupplementalFamilyIDs = familyIDsValue(
            argumentValue(named: "--screenshot-visible-supplemental-families", arguments: arguments)
                ?? environment["CODEX_TOOLBAR_SCREENSHOT_VISIBLE_SUPPLEMENTAL_FAMILIES"]
        )

        return ScreenshotLaunchConfiguration(
            scenario: scenario,
            appearance: appearance,
            outputDirectory: outputDirectory,
            shouldCapturePopover: shouldCapturePopover,
            shouldCaptureStatusItem: shouldCaptureStatusItem,
            shouldOpenPopover: shouldOpenPopover,
            visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs,
            showsOpenCodexButton: showsOpenCodexButton
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

    private static func optionalBoolValue(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }

        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func familyIDsValue(_ value: String?) -> Set<String>? {
        guard let value else {
            return nil
        }

        let familyIDs = value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Set(familyIDs)
    }
}
