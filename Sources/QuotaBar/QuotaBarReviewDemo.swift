import Foundation
import ToolbarCore

enum QuotaBarReviewDemo {
    static let userDefaultsKey = "QuotaBarDemoScenario"

    static func scenarioName(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultsSuiteName: String? = nil
    ) -> String? {
        if let launchConfiguration = ScreenshotLaunchConfiguration.current(arguments: arguments, environment: environment) {
            return launchConfiguration.scenario.name
        }

        if let explicitScenario = argumentValue(named: "--review-demo-scenario", arguments: arguments) {
            return explicitScenario
        }

        if hasFlag(named: "--review-demo", arguments: arguments)
            || boolValue(argumentValue(named: "--review-demo", arguments: arguments), defaultValue: false)
        {
            return "normal"
        }

        if let explicitScenario = environment["QUOTABAR_REVIEW_DEMO_SCENARIO"] {
            return explicitScenario
        }

        if boolValue(environment["QUOTABAR_REVIEW_DEMO"], defaultValue: false) {
            return "normal"
        }

        return defaults(for: defaultsSuiteName).string(forKey: userDefaultsKey)
    }

    static func scenario(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultsSuiteName: String? = nil
    ) -> ScreenshotScenario? {
        guard let scenarioName = scenarioName(arguments: arguments, environment: environment, defaultsSuiteName: defaultsSuiteName) else {
            return nil
        }

        return ScreenshotScenario.named(scenarioName)
    }

    static func setScenarioName(_ name: String?, defaultsSuiteName: String? = nil) {
        let defaults = defaults(for: defaultsSuiteName)
        if let name {
            defaults.set(name, forKey: userDefaultsKey)
        } else {
            defaults.removeObject(forKey: userDefaultsKey)
        }
    }

    private static func argumentValue(named flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    private static func hasFlag(named flag: String, arguments: [String]) -> Bool {
        arguments.contains(flag)
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

    private static func defaults(for suiteName: String?) -> UserDefaults {
        guard let suiteName, let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }

        return defaults
    }
}
