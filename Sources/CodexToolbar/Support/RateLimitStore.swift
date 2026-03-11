import Foundation
import Observation

@MainActor
@Observable
package final class RateLimitStore {
    private enum WindowRole {
        case primary
        case secondary
    }

    package enum State: Equatable {
        case idle
        case connecting
        case ready
        case error(String)
    }

    package var state: State = .idle
    package var cards: [RateLimitCardViewData] = []
    package var statusMessage: String
    package var lastUpdated: Date?
    package var staleMessage: String?
    package var debugDetail: String?

    private let client: any RateLimitClient
    private let presentation: ToolbarPresentation
    private let reconnectDelayNanoseconds: UInt64
    private let refreshDelayNanosecondsProvider: @Sendable () -> UInt64
    private let liveUpdatesEnabled: Bool
    private var started = false
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    package init(
        client: any RateLimitClient,
        presentation: ToolbarPresentation,
        reconnectDelayNanoseconds: UInt64 = 2_000_000_000,
        refreshDelayNanosecondsProvider: @escaping @Sendable () -> UInt64 = { RateLimitStore.defaultRefreshDelayNanoseconds() },
        initialState: State = .idle,
        initialCards: [RateLimitCardViewData] = [],
        initialStatusMessage: String? = nil,
        initialLastUpdated: Date? = nil,
        liveUpdatesEnabled: Bool = true
    ) {
        self.client = client
        self.presentation = presentation
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
        self.refreshDelayNanosecondsProvider = refreshDelayNanosecondsProvider
        self.liveUpdatesEnabled = liveUpdatesEnabled
        state = initialState
        cards = initialCards
        statusMessage = initialStatusMessage ?? presentation.connectingStatusMessage
        lastUpdated = initialLastUpdated
    }

    package func start() async {
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
                debugDetail = presentation.connectDebugDetail
                try await client.connect()
                if debugDetail == presentation.connectDebugDetail {
                    debugDetail = "Live updates connected"
                }
            } catch {
                debugDetail = "Connect failed: \(error.localizedDescription)"
                handleRefreshError(error, preserveCards: !cards.isEmpty)
                scheduleReconnect()
            }
        }

        await refreshNow(source: .startup)
    }

    package func stop() async {
        reconnectTask?.cancel()
        eventTask?.cancel()
        refreshTask?.cancel()
        reconnectTask = nil
        eventTask = nil
        refreshTask = nil
        started = false
        await client.disconnect()
    }

    package func refreshNow() async {
        await refreshNow(source: .manual)
    }

    package var statusBarText: String {
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
            statusMessage = presentation.connectingStatusMessage
        }
        staleMessage = nil
        debugDetail = "Refresh source: \(String(describing: source))"

        do {
            let refreshToken = source != .startup
            debugDetail = "Loading snapshot (refreshToken=\(refreshToken))"
            let (account, response) = try await client.loadSnapshot(refreshToken: refreshToken)
            debugDetail = "Snapshot loaded"

            if account.account == nil {
                debugDetail = "No signed-in account"
                applyError(presentation.signInRequiredMessage)
                return
            }

            apply(snapshot: response.displaySnapshot())
        } catch {
            handleRefreshError(error, preserveCards: !cards.isEmpty)
        }
    }

    private func handle(event: RateLimitClientEvent) async {
        switch event {
        case let .rateLimitsUpdated(response):
            apply(snapshot: response.displaySnapshot())
        case let .disconnected(reason):
            state = .error(presentation.disconnectedMessage)
            statusMessage = reason ?? "Retrying…"
            staleMessage = cards.isEmpty ? nil : (reason ?? presentation.disconnectedMessage)
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
            applyError(presentation.noDataMessage)
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

        if message == presentation.signInRequiredMessage || message == presentation.noDataMessage {
            cards = []
            staleMessage = nil
        }
    }

    private func handleRefreshError(_ error: Error, preserveCards: Bool) {
        let message: String

        if let clientError = error as? RateLimitClientError {
            message = clientError.localizedDescription
        } else {
            message = presentation.unableToLoadMessage
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

    package static func makeCards(
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

    package static func makeShared(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        presentation: ToolbarPresentation,
        clientFactory: @escaping () -> any RateLimitClient
    ) -> RateLimitStore {
        if let launchConfiguration = ScreenshotLaunchConfiguration.current(arguments: arguments, environment: environment) {
            let cards = makeCards(
                from: launchConfiguration.scenario.snapshot,
                now: launchConfiguration.scenario.now,
                calendar: launchConfiguration.scenario.calendar,
                locale: launchConfiguration.scenario.locale,
                timeZone: launchConfiguration.scenario.timeZone
            )
            let statusMessage = cards.isEmpty ? presentation.noDataMessage : "Rate limits remaining"
            let state: State = cards.isEmpty ? .error(statusMessage) : .ready

            return RateLimitStore(
                client: clientFactory(),
                presentation: presentation,
                initialState: state,
                initialCards: cards,
                initialStatusMessage: statusMessage,
                initialLastUpdated: launchConfiguration.scenario.lastUpdated,
                liveUpdatesEnabled: false
            )
        }

        return RateLimitStore(client: clientFactory(), presentation: presentation)
    }

    package nonisolated static func defaultRefreshDelayNanoseconds(now: Date = Date(), calendar: Calendar = .current) -> UInt64 {
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
                handleRefreshError(error, preserveCards: !cards.isEmpty)
                scheduleReconnect()
                return
            }
            await refreshNow(source: .reconnect)
        }
    }
}
