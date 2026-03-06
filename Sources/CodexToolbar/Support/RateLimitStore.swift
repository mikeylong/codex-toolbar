import Foundation
import Observation

@MainActor
@Observable
final class RateLimitStore {
    static let shared = RateLimitStore(client: CodexAppServerClient())

    enum State: Equatable {
        case idle
        case connecting
        case ready
        case error(String)
    }

    var state: State = .idle
    var cards: [RateLimitCardViewData] = []
    var statusMessage = "Connecting to Codex…"
    var lastUpdated: Date?

    private let client: any CodexRateLimitClient
    private let reconnectDelayNanoseconds: UInt64
    private let refreshDelayNanosecondsProvider: @Sendable () -> UInt64
    private var started = false
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        client: any CodexRateLimitClient,
        reconnectDelayNanoseconds: UInt64 = 2_000_000_000,
        refreshDelayNanosecondsProvider: @escaping @Sendable () -> UInt64 = { RateLimitStore.defaultRefreshDelayNanoseconds() }
    ) {
        self.client = client
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
        self.refreshDelayNanosecondsProvider = refreshDelayNanosecondsProvider
    }

    func start() async {
        guard !started else { return }
        started = true

        eventTask = Task { [weak self] in
            guard let self else { return }
            let events = client.events()
            for await event in events {
                await handle(event: event)
            }
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshDelayNanosecondsProvider())
                guard !Task.isCancelled else { return }
                await refreshNow(source: .timer)
            }
        }

        await refreshNow(source: .startup)
    }

    func stop() async {
        reconnectTask?.cancel()
        eventTask?.cancel()
        refreshTask?.cancel()
        reconnectTask = nil
        eventTask = nil
        refreshTask = nil
        started = false
        await client.disconnect()
    }

    func refreshNow() async {
        await refreshNow(source: .manual)
    }

    var statusBarText: String {
        if let primaryCard = cards.first {
            return "\(primaryCard.remainingPercent)% \(primaryCard.compactLabel)"
        }

        switch state {
        case .idle, .connecting:
            return "--"
        case .ready:
            return "--"
        case .error:
            return "!"
        }
    }

    private enum RefreshSource {
        case startup
        case timer
        case manual
        case reconnect
    }

    private func refreshNow(source: RefreshSource) async {
        state = .connecting
        if cards.isEmpty || source == .manual {
            statusMessage = "Connecting to Codex…"
        }

        do {
            let (account, response) = try await client.loadSnapshot()

            if account.account == nil {
                applyError("Sign in to Codex to view rate limits.")
                return
            }

            apply(snapshot: response.codexSnapshot())
        } catch let error as CodexAppServerError {
            switch error {
            case .codexCLINotFound:
                applyError("Codex CLI not found.")
            default:
                applyError(error.localizedDescription)
                scheduleReconnect()
            }
        } catch {
            applyError("Unable to load Codex rate limits.")
            scheduleReconnect()
        }
    }

    private func handle(event: CodexAppServerEvent) async {
        switch event {
        case let .rateLimitsUpdated(response):
            apply(snapshot: response.codexSnapshot())
        case let .disconnected(reason):
            state = .error("Disconnected from Codex.")
            statusMessage = reason ?? "Retrying…"
            scheduleReconnect()
        case .stderr:
            break
        }
    }

    private func apply(snapshot: CodexRateLimitsSnapshot) {
        cards = Self.makeCards(from: snapshot)
        lastUpdated = Date()

        if cards.isEmpty {
            applyError("No rate-limit data available.")
            return
        }

        state = .ready
        statusMessage = "Rate limits remaining"
    }

    private func applyError(_ message: String) {
        state = .error(message)
        statusMessage = message

        if message == "Sign in to Codex to view rate limits." || message == "No rate-limit data available." {
            cards = []
        }
    }

    static func makeCards(
        from snapshot: CodexRateLimitsSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RateLimitCardViewData] {
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        let sorted = windows.sorted {
            if $0.usedPercent == $1.usedPercent {
                return ($0.windowDurationMins ?? .max) < ($1.windowDurationMins ?? .max)
            }
            return $0.usedPercent > $1.usedPercent
        }

        return sorted.enumerated().map { index, window in
            RateLimitCardViewData(window: window, isPrimary: index == 0, now: now, calendar: calendar)
        }
    }

    nonisolated static func defaultRefreshDelayNanoseconds(now: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        let currentSecond = calendar.component(.second, from: now)
        let currentNanosecond = calendar.component(.nanosecond, from: now)

        let remainingSeconds = max(0, 59 - currentSecond)
        let remainingNanoseconds = max(0, 1_000_000_000 - currentNanosecond)
        let totalNanoseconds = UInt64(remainingSeconds) * 1_000_000_000 + UInt64(remainingNanoseconds)

        return max(totalNanoseconds, 1_000_000)
    }

    private func scheduleReconnect() {
        guard started else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await refreshNow(source: .reconnect)
        }
    }
}
