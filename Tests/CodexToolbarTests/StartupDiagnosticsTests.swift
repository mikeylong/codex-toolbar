import Foundation
import XCTest
@testable import CodexToolbar

@MainActor
final class StartupDiagnosticsTests: XCTestCase {
    func testReadyStateWithCardsIsValidFirstRunState() {
        let store = RateLimitStore(
            client: FakeStartupDiagnosticsClient(),
            initialState: .ready,
            initialCards: [RateLimitCardViewData(window: makeWindow(usedPercent: 19, durationMinutes: 300))],
            initialStatusMessage: "Rate limits remaining",
            initialLastUpdated: Date(),
            liveUpdatesEnabled: false
        )

        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: "Launch at login disabled")

        XCTAssertTrue(record.isValidFirstRunState)
        XCTAssertEqual(record.state, "ready")
        XCTAssertEqual(record.cardCount, 1)
    }

    func testExpectedErrorStateIsValidFirstRunState() {
        let store = RateLimitStore(
            client: FakeStartupDiagnosticsClient(),
            initialState: .error("Codex CLI not found."),
            initialCards: [],
            initialStatusMessage: "Codex CLI not found.",
            liveUpdatesEnabled: false
        )

        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: "Launch at login disabled")

        XCTAssertTrue(record.isValidFirstRunState)
        XCTAssertEqual(record.state, "error")
    }

    func testConnectingStateIsNotValidFirstRunState() {
        let store = RateLimitStore(
            client: FakeStartupDiagnosticsClient(),
            initialState: .connecting,
            initialCards: [],
            initialStatusMessage: "Connecting to Codex…",
            liveUpdatesEnabled: false
        )

        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: "Launch at login disabled")

        XCTAssertFalse(record.isValidFirstRunState)
    }

    private func makeWindow(usedPercent: Int, durationMinutes: Int) -> CodexRateLimitWindow {
        CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: usedPercent, windowDurationMins: durationMinutes)
    }
}

private final class FakeStartupDiagnosticsClient: @unchecked Sendable, CodexRateLimitClient {
    func events() -> AsyncStream<CodexAppServerEvent> {
        AsyncStream { _ in }
    }

    func connect() async throws {}

    func disconnect() async {}

    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse {
        GetAccountResponse(account: nil, requiresOpenaiAuth: false)
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        GetAccountRateLimitsResponse(
            rateLimits: CodexRateLimitsSnapshot(
                credits: nil,
                limitId: nil,
                limitName: nil,
                planType: nil,
                primary: nil,
                secondary: nil
            ),
            rateLimitsByLimitId: nil
        )
    }

    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        (try await readAccount(refreshToken: refreshToken), try await readRateLimits())
    }

}
