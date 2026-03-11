import Foundation
import XCTest
@testable import ToolbarCore
@testable import QuotaBar

final class QuotaBarTests: XCTestCase {
    func testReviewDemoPrefersExplicitScenarioArgument() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let scenarioName = QuotaBarReviewDemo.scenarioName(
            arguments: ["QuotaBar", "--review-demo-scenario", "critical"],
            environment: [:],
            defaultsSuiteName: #function
        )

        XCTAssertEqual(scenarioName, "critical")
    }

    func testReviewDemoFlagDefaultsToNormalScenario() {
        let scenarioName = QuotaBarReviewDemo.scenarioName(
            arguments: ["QuotaBar", "--review-demo"],
            environment: [:]
        )

        XCTAssertEqual(scenarioName, "normal")
    }

    func testRateLimitClientLoadsFixtureScenarioWhenDemoEnabled() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set("warning", forKey: QuotaBarReviewDemo.userDefaultsKey)

        let client = QuotaBarRateLimitClient(arguments: ["QuotaBar"], environment: [:], defaultsSuiteName: #function)
        let (_, response) = try await client.loadSnapshot(refreshToken: false)

        XCTAssertEqual(response.rateLimits.primary?.usedPercent, ScreenshotScenario.warning.snapshot.primary?.usedPercent)
        XCTAssertEqual(response.rateLimits.secondary?.usedPercent, ScreenshotScenario.warning.snapshot.secondary?.usedPercent)
    }

    func testRateLimitClientSurfacesReviewMessageWhenNoScenarioIsSelected() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let client = QuotaBarRateLimitClient(arguments: ["QuotaBar"], environment: [:], defaultsSuiteName: #function)

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected readRateLimits to fail without a review scenario.")
        } catch let error as RateLimitClientError {
            XCTAssertEqual(error, .serverError(QuotaBarReleaseGate.reviewMessage))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
