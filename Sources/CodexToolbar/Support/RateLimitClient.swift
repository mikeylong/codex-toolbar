import Foundation

package protocol RateLimitClient: Sendable {
    func events() -> AsyncStream<RateLimitClientEvent>
    func connect() async throws
    func disconnect() async
    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse
    func readRateLimits() async throws -> GetAccountRateLimitsResponse
    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse)
}

package enum RateLimitClientEvent: Sendable {
    case rateLimitsUpdated(GetAccountRateLimitsResponse)
    case disconnected(String?)
    case stderr(String)
}

package enum RateLimitClientError: LocalizedError, Sendable, Equatable {
    case clientUnavailable(String)
    case invalidResponse(String)
    case serverError(String)
    case transportClosed(String)

    package var errorDescription: String? {
        switch self {
        case let .clientUnavailable(message),
             let .invalidResponse(message),
             let .serverError(message),
             let .transportClosed(message):
            return message
        }
    }
}
