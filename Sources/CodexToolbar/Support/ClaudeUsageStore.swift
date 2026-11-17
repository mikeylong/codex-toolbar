import Foundation
import Observation

@MainActor
@Observable
final class ClaudeUsageStore {
    nonisolated static let staleRefreshMaximumAge: TimeInterval = 300

    private(set) var windows: [ClaudeUsageWindow]
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var statusMessage: String?
    private(set) var isStale = false
    private var hasError = false

    private let client: any ClaudeUsageClient
    private let refreshInterval: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private let liveUpdatesEnabled: Bool
    private var started = false
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var activeRequestGeneration: Int?

    init(
        client: any ClaudeUsageClient = ClaudeCLIUsageClient(),
        refreshInterval: TimeInterval = ClaudeUsageStore.staleRefreshMaximumAge,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        initialSnapshot: ClaudeUsageSnapshot? = nil,
        initialLastUpdated: Date? = nil,
        liveUpdatesEnabled: Bool = true
    ) {
        self.client = client
        self.refreshInterval = refreshInterval.isFinite ? max(refreshInterval, 0.01) : Self.staleRefreshMaximumAge
        self.nowProvider = nowProvider
        self.liveUpdatesEnabled = liveUpdatesEnabled
        windows = initialSnapshot?.windows ?? []
        lastUpdated = initialLastUpdated
        statusMessage = initialSnapshot == nil ? "Loading Claude usage…" : nil
    }

    var windowViewData: [ClaudeUsageWindowViewData] {
        windows.map(ClaudeUsageWindowViewData.init)
    }

    var statusItemPresentation: RateLimitStore.StatusItemPresentation {
        guard !hasError, !isStale else { return .text("!") }
        guard let window = preferredStatusBarWindow else { return .text("--") }
        return .bar(RateLimitStore.StatusItemBarPresentation(
            remainingPercent: window.remainingPercent,
            progressState: RateLimitProgressState(remainingPercent: window.remainingPercent)
        ))
    }

    var statusItemTooltipText: String {
        if isStale {
            var text = "Claude usage is stale."
            if let window = preferredStatusBarWindow {
                text += " Last known \(window.title): \(window.remainingPercent)% remaining."
            }
            if let lastUpdated {
                text += " \(RateLimitFormatter.updatedFooterText(for: lastUpdated))."
            }
            if let statusMessage { text += " \(statusMessage)" }
            return text
        }
        if hasError {
            return "Claude: \(statusMessage ?? "Usage unavailable.")"
        }
        guard let window = preferredStatusBarWindow else {
            return "Claude: \(statusMessage ?? "Core usage limits unavailable.")"
        }
        var text = "Claude · \(window.title): \(window.remainingPercent)% remaining"
        if let resetDescription = window.resetDescription { text += ". \(resetDescription)" }
        if isLoading { text += ". Refreshing…" }
        return text
    }

    var statusBarAccessibilityText: String {
        statusItemTooltipText
    }

    private var preferredStatusBarWindow: ClaudeUsageWindowViewData? {
        // Model-specific weekly limits must not replace the account-wide
        // session/weekly indicator, even when that model is exhausted.
        windowViewData.filter(\.isCoreWindow).sorted { lhs, rhs in
            if lhs.remainingPercent == rhs.remainingPercent { return lhs.title < rhs.title }
            return lhs.remainingPercent < rhs.remainingPercent
        }.first
    }

    func prepareForTermination() -> Bool {
        started = false
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        requestTask?.cancel()
        isLoading = false
        // Wait on the process worker directly, not on its main-actor result
        // task: AppKit's termination loop can suspend that executor.
        return client.cancelForTermination()
    }

    func start() async {
        guard !started, liveUpdatesEnabled else { return }
        started = true
        let interval = refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refreshNow()
            }
        }
        await refreshNow()
    }

    func stop() async {
        started = false
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        requestTask?.cancel()
        isLoading = false
        await requestTask?.value
    }

    func refreshIfNeeded(maxAge: TimeInterval = ClaudeUsageStore.staleRefreshMaximumAge) async {
        if let lastUpdated, !isStale, nowProvider().timeIntervalSince(lastUpdated) < maxAge {
            return
        }
        await refreshNow()
    }

    func refreshNow() async {
        guard liveUpdatesEnabled, !Task.isCancelled else { return }
        if let requestTask {
            let callerGeneration = generation
            let waitingGeneration = activeRequestGeneration
            await requestTask.value
            // A stopped request must finish before a new one can begin, even
            // when a client takes time to respond to cancellation.
            if callerGeneration == generation, waitingGeneration != generation, !Task.isCancelled {
                await refreshNow()
            }
            return
        }

        let requestGeneration = generation
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                requestTask = nil
                activeRequestGeneration = nil
                isLoading = false
            }
            do {
                let snapshot = try await client.readUsage()
                guard generation == requestGeneration, !Task.isCancelled else { return }
                windows = snapshot.windows
                lastUpdated = nowProvider()
                isStale = false
                hasError = false
                statusMessage = windows.isEmpty ? "No Claude usage limits available." : nil
            } catch {
                guard generation == requestGeneration, !Task.isCancelled else { return }
                hasError = true
                if let usageError = error as? ClaudeUsageError,
                   usageError == .notAuthenticated || usageError == .notSubscription
                {
                    windows = []
                    lastUpdated = nil
                    isStale = false
                } else {
                    isStale = !windows.isEmpty
                }
                statusMessage = error.localizedDescription
            }
        }
        activeRequestGeneration = requestGeneration
        requestTask = task
        await task.value
    }
}

struct ClaudeUsageWindowViewData: Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Int
    let remainingPercent: Int
    let resetDescription: String?

    init(window: ClaudeUsageWindow) {
        id = window.id
        title = window.title
        usedPercent = min(max(window.usedPercent, 0), 100)
        remainingPercent = 100 - usedPercent
        resetDescription = window.resetDescription
    }

    var usageText: String {
        "\(usedPercent)% used · \(remainingPercent)% remaining"
    }

    var isCoreWindow: Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["session", "current session", "weekly", "current week", "weekly (all models)", "current week (all models)"]
            .contains(normalizedTitle)
    }

    var accessibilityLabel: String {
        ["Claude \(title)", "\(usedPercent)% used", "\(remainingPercent)% remaining", resetDescription]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}
