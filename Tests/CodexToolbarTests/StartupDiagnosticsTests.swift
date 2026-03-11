import Foundation
import XCTest
@testable import ToolbarCore

@MainActor
final class StartupDiagnosticsTests: XCTestCase {
    func testReadyStateWithCardsIsValidFirstRunState() {
        let store = RateLimitStore(
            client: FakeStartupDiagnosticsClient(),
            presentation: .testPresentation,
            initialState: .ready,
            initialCards: [RateLimitCardViewData(window: makeWindow(usedPercent: 19, durationMinutes: 300))],
            initialStatusMessage: "Rate limits remaining",
            initialLastUpdated: Date(),
            liveUpdatesEnabled: false
        )

        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: "Launch at login disabled")

        XCTAssertTrue(record.isValidFirstRunState(validErrorMessages: ToolbarPresentation.testPresentation.validStartupErrorMessages))
        XCTAssertEqual(record.state, "ready")
        XCTAssertEqual(record.cardCount, 1)
    }

    func testExpectedErrorStateIsValidFirstRunState() {
        let store = RateLimitStore(
            client: FakeStartupDiagnosticsClient(),
            presentation: .testPresentation,
            initialState: .error("Client unavailable."),
            initialCards: [],
            initialStatusMessage: "Client unavailable.",
            liveUpdatesEnabled: false
        )

        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: "Launch at login disabled")

        XCTAssertTrue(record.isValidFirstRunState(validErrorMessages: ToolbarPresentation.testPresentation.validStartupErrorMessages))
        XCTAssertEqual(record.state, "error")
    }

    func testConnectingStateIsNotValidFirstRunState() {
        let store = RateLimitStore(
            client: FakeStartupDiagnosticsClient(),
            presentation: .testPresentation,
            initialState: .connecting,
            initialCards: [],
            initialStatusMessage: "Connecting…",
            liveUpdatesEnabled: false
        )

        let record = StartupDiagnosticsRecord(store: store, loginItemStatus: "Launch at login disabled")

        XCTAssertFalse(record.isValidFirstRunState(validErrorMessages: ToolbarPresentation.testPresentation.validStartupErrorMessages))
    }

    private func makeWindow(usedPercent: Int, durationMinutes: Int) -> CodexRateLimitWindow {
        CodexRateLimitWindow(resetsAt: 1_741_171_240, usedPercent: usedPercent, windowDurationMins: durationMinutes)
    }
}

private final class FakeStartupDiagnosticsClient: @unchecked Sendable, RateLimitClient {
    func events() -> AsyncStream<RateLimitClientEvent> {
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
