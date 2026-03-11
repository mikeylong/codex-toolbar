import Foundation
import ToolbarCore

actor QuotaBarRateLimitClient: RateLimitClient {
    private let arguments: [String]
    private let environment: [String: String]
    private let defaultsSuiteName: String?

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultsSuiteName: String? = nil
    ) {
        self.arguments = arguments
        self.environment = environment
        self.defaultsSuiteName = defaultsSuiteName
    }

    nonisolated func events() -> AsyncStream<RateLimitClientEvent> {
        AsyncStream { _ in }
    }

    func connect() async throws {}

    func disconnect() async {}

    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse {
        guard currentScenario() != nil else {
            throw RateLimitClientError.clientUnavailable(QuotaBarReleaseGate.unavailableMessage)
        }

        return GetAccountResponse(
            account: .chatgpt(email: "demo@quotabar.app", planType: .pro),
            requiresOpenaiAuth: false
        )
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        guard let scenario = currentScenario() else {
            throw RateLimitClientError.serverError(
                QuotaBarReviewDemo.scenarioName(
                    arguments: arguments,
                    environment: environment,
                    defaultsSuiteName: defaultsSuiteName
                ) == nil ? QuotaBarReleaseGate.reviewMessage : QuotaBarReleaseGate.unavailableMessage
            )
        }

        return GetAccountRateLimitsResponse(
            rateLimits: scenario.snapshot,
            rateLimitsByLimitId: nil
        )
    }

    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        (try await readAccount(refreshToken: refreshToken), try await readRateLimits())
    }

    private func currentScenario() -> ScreenshotScenario? {
        QuotaBarReviewDemo.scenario(
            arguments: arguments,
            environment: environment,
            defaultsSuiteName: defaultsSuiteName
        )
    }
}
