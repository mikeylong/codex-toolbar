import Foundation
import Observation

@MainActor
@Observable
final class RateLimitStore {
    private static let signInMessage = "Sign in to Codex to view rate limits."
    private static let codexCLINotFoundMessage = "Codex CLI not found."
    private static let noRateLimitDataMessage = "No rate-limit data available."

    private enum WindowRole {
        case primary
        case secondary
    }

    static let shared = makeShared()

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
    var staleMessage: String?
    var debugDetail: String?

    private let client: any CodexRateLimitClient
    private let reconnectDelayNanoseconds: UInt64
    private let refreshDelayNanosecondsProvider: @Sendable () -> UInt64
    private let liveUpdatesEnabled: Bool
    private var started = false
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        client: any CodexRateLimitClient,
        reconnectDelayNanoseconds: UInt64 = 2_000_000_000,
        refreshDelayNanosecondsProvider: @escaping @Sendable () -> UInt64 = { RateLimitStore.defaultRefreshDelayNanoseconds() },
        initialState: State = .idle,
        initialCards: [RateLimitCardViewData] = [],
        initialStatusMessage: String = "Connecting to Codex…",
        initialLastUpdated: Date? = nil,
        liveUpdatesEnabled: Bool = true
    ) {
        self.client = client
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
        self.refreshDelayNanosecondsProvider = refreshDelayNanosecondsProvider
        self.liveUpdatesEnabled = liveUpdatesEnabled
        state = initialState
        cards = initialCards
        statusMessage = initialStatusMessage
        lastUpdated = initialLastUpdated
    }

    func start() async {
        guard !started else { return }
        started = true

        guard liveUpdatesEnabled else { return }

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

        Task { [weak self] in
            guard let self else { return }
            do {
                debugDetail = "Connecting to Codex app-server"
                try await client.connect()
                if debugDetail == "Connecting to Codex app-server" {
                    debugDetail = "Live updates connected"
                }
            } catch {
                debugDetail = "Connect failed: \(error.localizedDescription)"
                await handleRefreshError(error, preserveCards: !cards.isEmpty)
                scheduleReconnect()
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
        switch state {
        case .idle, .connecting:
            return cards.first.map { "\($0.remainingPercent)% \($0.compactLabel)" } ?? "--"
        case .ready:
            return cards.first.map { "\($0.remainingPercent)% \($0.compactLabel)" } ?? "--"
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
        staleMessage = nil
        debugDetail = "Refresh source: \(String(describing: source))"

        do {
            if try await shouldApplyLoggedOutErrorBeforeSnapshot(for: source) {
                return
            }

            let refreshToken = source != .startup
            debugDetail = "Loading snapshot (refreshToken=\(refreshToken))"
            let (account, response) = try await client.loadSnapshot(refreshToken: refreshToken)
            debugDetail = "Snapshot loaded"

            if account.account == nil {
                debugDetail = "No signed-in account"
                applyError(Self.signInMessage)
                return
            }

            apply(snapshot: response.displaySnapshot())
        } catch let error as CodexAppServerError {
            await handleRefreshError(error, preserveCards: !cards.isEmpty)
        } catch {
            await handleRefreshError(error, preserveCards: !cards.isEmpty)
        }
    }

    private func handle(event: CodexAppServerEvent) async {
        switch event {
        case let .rateLimitsUpdated(response):
            apply(snapshot: response.displaySnapshot())
        case let .disconnected(reason):
            state = .error("Disconnected from Codex.")
            statusMessage = reason ?? "Retrying…"
            staleMessage = cards.isEmpty ? nil : (reason ?? "Disconnected from Codex.")
            scheduleReconnect()
        case .stderr:
            break
        }
    }

    private func apply(snapshot: CodexRateLimitsSnapshot) {
        cards = Self.makeCards(from: snapshot)
        lastUpdated = Date()

        if cards.isEmpty {
            debugDetail = "Snapshot contained no cards"
            applyError(Self.noRateLimitDataMessage)
            return
        }

        state = .ready
        statusMessage = "Rate limits remaining"
        staleMessage = nil
        debugDetail = "Ready"
    }

    private func applyError(_ message: String) {
        state = .error(message)
        statusMessage = message
        staleMessage = cards.isEmpty ? nil : message
        debugDetail = message

        if message == Self.signInMessage || message == Self.noRateLimitDataMessage {
            cards = []
            staleMessage = nil
        }
    }

    private func handleRefreshError(_ error: Error, preserveCards: Bool) async {
        if await shouldMapToSignInError(error) {
            if preserveCards {
                state = .error(Self.signInMessage)
                statusMessage = Self.signInMessage
                staleMessage = Self.signInMessage
                debugDetail = Self.signInMessage
                scheduleReconnect()
            } else {
                applyError(Self.signInMessage)
                scheduleReconnect()
            }
            return
        }

        let message: String

        if let appServerError = error as? CodexAppServerError {
            switch appServerError {
            case .codexCLINotFound:
                message = Self.codexCLINotFoundMessage
            default:
                message = appServerError.localizedDescription
            }
        } else {
            message = "Unable to load Codex rate limits."
        }

        if preserveCards {
            state = .error(message)
            statusMessage = message
            staleMessage = message
            scheduleReconnect()
        } else {
            applyError(message)
            scheduleReconnect()
        }
    }

    private func shouldApplyLoggedOutErrorBeforeSnapshot(for source: RefreshSource) async throws -> Bool {
        guard shouldPreflightLoginStatus(for: source) else {
            return false
        }

        let loginStatus = try await client.readLoginStatus()
        switch loginStatus {
        case .loggedIn:
            return false
        case .loggedOut:
            debugDetail = "Codex login status: logged out"
            applyError(Self.signInMessage)
            return true
        case let .indeterminate(detail):
            if let detail {
                debugDetail = "Codex login status indeterminate: \(detail)"
            }
            return false
        }
    }

    private func shouldPreflightLoginStatus(for source: RefreshSource) -> Bool {
        switch source {
        case .startup, .manual, .reconnect:
            return true
        case .timer:
            return cards.isEmpty || statusMessage == Self.signInMessage || staleMessage == Self.signInMessage
        }
    }

    private func shouldMapToSignInError(_ error: Error) async -> Bool {
        guard isSnapshotTimeout(error) else {
            return false
        }

        do {
            let loginStatus = try await client.readLoginStatus()
            if case .loggedOut = loginStatus {
                debugDetail = "Codex login status fallback: logged out"
                return true
            }
        } catch {
            debugDetail = "Codex login status fallback failed: \(error.localizedDescription)"
        }

        return false
    }

    private func isSnapshotTimeout(_ error: Error) -> Bool {
        guard case let .serverError(message) = error as? CodexAppServerError else {
            return false
        }

        return message.contains("Timed out reading Codex rate limits.")
    }

    static func makeCards(
        from snapshot: CodexRateLimitsSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [RateLimitCardViewData] {
        let windows = [
            (window: snapshot.primary, role: WindowRole.primary),
            (window: snapshot.secondary, role: WindowRole.secondary)
        ].compactMap { entry in
            entry.window.map { (window: $0, role: entry.role) }
        }

        let sorted = windows.sorted {
            if $0.window.usedPercent == $1.window.usedPercent {
                return ($0.window.windowDurationMins ?? .max) < ($1.window.windowDurationMins ?? .max)
            }
            return $0.window.usedPercent > $1.window.usedPercent
        }

        return sorted.enumerated().map { index, entry in
            RateLimitCardViewData(
                window: entry.window,
                displayLabelOverride: displayLabelOverride(
                    role: entry.role,
                    snapshot: snapshot
                ),
                isPrimary: index == 0,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        }
    }

    private static func displayLabelOverride(
        role: WindowRole,
        snapshot: CodexRateLimitsSnapshot
    ) -> String? {
        guard snapshot.limitId == "codex" else {
            return nil
        }

        switch role {
        case .primary:
            return "5h"
        case .secondary:
            return "Weekly"
        }
    }

    static func makeShared(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        clientFactory: @escaping () -> any CodexRateLimitClient = { CodexAppServerClient() }
    ) -> RateLimitStore {
        if let launchConfiguration = ScreenshotLaunchConfiguration.current(arguments: arguments, environment: environment) {
            let cards = makeCards(
                from: launchConfiguration.scenario.snapshot,
                now: launchConfiguration.scenario.now,
                calendar: launchConfiguration.scenario.calendar,
                locale: launchConfiguration.scenario.locale,
                timeZone: launchConfiguration.scenario.timeZone
            )
            let statusMessage = cards.isEmpty ? "No rate-limit data available." : "Rate limits remaining"
            let state: State = cards.isEmpty ? .error(statusMessage) : .ready

            return RateLimitStore(
                client: clientFactory(),
                initialState: state,
                initialCards: cards,
                initialStatusMessage: statusMessage,
                initialLastUpdated: launchConfiguration.scenario.lastUpdated,
                liveUpdatesEnabled: false
            )
        }

        return RateLimitStore(client: clientFactory())
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
            do {
                try await client.connect()
            } catch {
                await handleRefreshError(error, preserveCards: !cards.isEmpty)
                scheduleReconnect()
                return
            }
            await refreshNow(source: .reconnect)
        }
    }
}
