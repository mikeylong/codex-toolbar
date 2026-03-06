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
    var primaryRow: RateLimitRowViewData?
    var secondaryRow: RateLimitRowViewData?
    var statusMessage = "Connecting to Codex…"
    var lastUpdated: Date?

    private let client: any CodexRateLimitClient
    private let reconnectDelayNanoseconds: UInt64
    private let refreshIntervalNanoseconds: UInt64
    private var started = false
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        client: any CodexRateLimitClient,
        reconnectDelayNanoseconds: UInt64 = 2_000_000_000,
        refreshIntervalNanoseconds: UInt64 = 60_000_000_000
    ) {
        self.client = client
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
        self.refreshIntervalNanoseconds = refreshIntervalNanoseconds
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
                try? await Task.sleep(nanoseconds: refreshIntervalNanoseconds)
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
        if let primaryRow {
            return primaryRow.percentText
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

    var rows: [RateLimitRowViewData] {
        [primaryRow, secondaryRow].compactMap { $0 }
    }

    private enum RefreshSource {
        case startup
        case timer
        case manual
        case reconnect
    }

    private func refreshNow(source: RefreshSource) async {
        state = .connecting
        if primaryRow == nil || source == .manual {
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
        primaryRow = snapshot.primary.map { RateLimitRowViewData(window: $0) }
        secondaryRow = snapshot.secondary.map { RateLimitRowViewData(window: $0) }
        lastUpdated = Date()

        if rows.isEmpty {
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
            primaryRow = nil
            secondaryRow = nil
        }
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
