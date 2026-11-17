import AppKit
import Darwin
import Observation
import SwiftUI

@MainActor
protocol AppRuntimeControlling {
    func terminate()
    func postNotification(title: String, body: String)
    func openURL(_ url: URL) throws
    func promptForSecret(title: String, message: String) -> String?
    func chooseUsageProviders(current: UsageProviderSelection?) -> UsageProviderSelection?
}

@MainActor
private struct LiveAppRuntimeController: AppRuntimeControlling {
    func terminate() {
        NSApplication.shared.terminate(nil)
    }

    func postNotification(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            NotificationAppleScriptBuilder.script(title: title, body: body)
        ]
        try? process.run()
    }

    func openURL(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw AppRuntimeError.openURLFailed(url)
        }
    }

    func chooseUsageProviders(current: UsageProviderSelection?) -> UsageProviderSelection? {
        let chooser = UsageProviderChooser(current: current)
        return chooser.runModal()
    }

    func promptForSecret(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        inputField.placeholderString = "OPENAI_ADMIN_KEY"
        alert.accessoryView = inputField

        return alert.runModal() == .alertFirstButtonReturn ? inputField.stringValue : nil
    }
}

private enum AppRuntimeError: LocalizedError {
    case openURLFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .openURLFailed(url):
            return "Unable to open \(url.absoluteString)."
        }
    }
}

@main
enum CodexToolbarLauncher {
    @MainActor
    static func main() {
        do {
            let plan = try AppLaunchBootstrap.plan(
                bundleURL: Bundle.main.bundleURL,
                bundleIdentifier: Bundle.main.bundleIdentifier,
                operatingSystemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                parentProcessID: getppid(),
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment
            )
            switch plan {
            case .runApplication:
                if #available(macOS 15.0, *) {
                    CodexToolbarMenuBarApp.main()
                } else {
                    CodexToolbarApp.main()
                }
            case let .openBundle(arguments):
                try AppLaunchBootstrap.openBundle(arguments: arguments)
            }
        } catch {
            fputs("CodexToolbar launch failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

struct CodexToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@available(macOS 15.0, *)
private struct CodexToolbarMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: RateLimitStore
    private let openAIUsageStore: OpenAIUsageStore
    private let claudeUsageStore: ClaudeUsageStore
    private let loginItemController: LoginItemController
    private let gitUpdateController: GitUpdateController
    private let codexDesktopAppProvider: any CodexDesktopAppProviding
    private let preferences: ToolbarPreferences
    private let maintenanceLaunchConfiguration: MaintenanceLaunchConfiguration?
    private let screenshotConfiguration: ScreenshotLaunchConfiguration?
    private let startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration?
    private let appRuntime: any AppRuntimeControlling
    private var statusItems: [UsageProvider: NSStatusItem] = [:]
    private var popovers: [UsageProvider: NSPopover] = [:]
    private var lifecycleTasks: [UsageProvider: Task<Void, Never>] = [:]
    private var screenshotProvider: UsageProvider {
        screenshotConfiguration?.scenario.claudeUsageSnapshot == nil ? .codex : .claude
    }
    private var statusItem: NSStatusItem? { statusItems[screenshotProvider] }
    private var popover: NSPopover? { popovers[screenshotProvider] }
    private var startupDiagnosticsDidFinish = false
    var popoverCloseHandler: (() -> Void)?

    override init() {
        store = .shared
        preferences = .shared
        openAIUsageStore = OpenAIUsageStore(isEnabled: true)
        loginItemController = .shared
        gitUpdateController = .shared
        codexDesktopAppProvider = CodexDesktopAppController()
        maintenanceLaunchConfiguration = MaintenanceLaunchConfiguration.current()
        screenshotConfiguration = ScreenshotLaunchConfiguration.current()
        claudeUsageStore = ClaudeUsageStore(
            initialSnapshot: screenshotConfiguration?.scenario.claudeUsageSnapshot,
            initialLastUpdated: screenshotConfiguration?.scenario.lastUpdated,
            liveUpdatesEnabled: screenshotConfiguration == nil
        )
        startupDiagnosticsConfiguration = StartupDiagnosticsConfiguration.current()
        appRuntime = LiveAppRuntimeController()
        super.init()
    }

    init(
        store: RateLimitStore,
        openAIUsageStore: OpenAIUsageStore = OpenAIUsageStore(isEnabled: true),
        claudeUsageStore: ClaudeUsageStore = ClaudeUsageStore(),
        loginItemController: LoginItemController,
        gitUpdateController: GitUpdateController,
        codexDesktopAppProvider: any CodexDesktopAppProviding,
        preferences: ToolbarPreferences = .shared,
        maintenanceLaunchConfiguration: MaintenanceLaunchConfiguration?,
        screenshotConfiguration: ScreenshotLaunchConfiguration?,
        startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration?,
        appRuntime: any AppRuntimeControlling = LiveAppRuntimeController()
    ) {
        self.store = store
        self.openAIUsageStore = openAIUsageStore
        self.claudeUsageStore = claudeUsageStore
        self.loginItemController = loginItemController
        self.gitUpdateController = gitUpdateController
        self.codexDesktopAppProvider = codexDesktopAppProvider
        self.preferences = preferences
        self.maintenanceLaunchConfiguration = maintenanceLaunchConfiguration
        self.screenshotConfiguration = screenshotConfiguration
        self.startupDiagnosticsConfiguration = startupDiagnosticsConfiguration
        self.appRuntime = appRuntime
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let maintenanceLaunchConfiguration {
            runMaintenanceAction(maintenanceLaunchConfiguration)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = screenshotConfiguration?.appearance.appAppearance
        guard configureProviderSelectionIfNeeded() else {
            appRuntime.terminate()
            return
        }
        configureProviderItems()
        observeState()
        updateStatusItem()
        synchronizeProviderLifecycle()
        gitUpdateController.start()
        maybeReportStartupDiagnostics()
        scheduleScreenshotCaptureIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if claudeUsageStore.prepareForTermination() {
            return .terminateNow
        }
        appRuntime.postNotification(title: "Claude usage is still stopping", body: "Try quitting CodexToolbar again in a moment.")
        return .terminateCancel
    }

    private func runMaintenanceAction(_ configuration: MaintenanceLaunchConfiguration) {
        NSApp.setActivationPolicy(.prohibited)

        let result = MaintenanceActionRunner(loginItemController: loginItemController)
            .run(configuration: configuration)

        let output = "\(result.message)\n"
        if result.exitCode == 0 {
            fputs(output, stdout)
        } else {
            fputs(output, stderr)
        }

        fflush(stdout)
        fflush(stderr)
        exit(result.exitCode)
    }

    var enabledProviders: [UsageProvider] {
        if screenshotConfiguration?.scenario.name == "providers" { return UsageProvider.allCases }
        if screenshotConfiguration != nil { return [screenshotProvider] }
        // The existing startup smoke-test record is a Codex readiness probe.
        // Keep its behavior deterministic without changing the saved choice.
        if startupDiagnosticsConfiguration != nil { return [.codex] }
        return (preferences.usageProviderSelection ?? .codex).providers
    }

    func configureProviderSelectionIfNeeded() -> Bool {
        guard screenshotConfiguration == nil, startupDiagnosticsConfiguration == nil,
              preferences.usageProviderSelection == nil else { return true }
        guard let selection = appRuntime.chooseUsageProviders(current: nil) else { return false }
        preferences.setUsageProviderSelection(selection)
        return true
    }

    private func configureProviderItems() {
        for popover in popovers.values { popover.performClose(nil) }
        for item in statusItems.values { NSStatusBar.system.removeStatusItem(item) }
        statusItems.removeAll()
        popovers.removeAll()
        for provider in enabledProviders {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "CodexToolbar.\(provider.rawValue)"
            statusItems[provider] = item
            if let button = item.button {
                button.target = self
                button.action = #selector(handleStatusItemClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.setAccessibilityLabel("\(provider.title) usage")
            }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = popoverContentSize(for: provider)
            popover.contentViewController = NSHostingController(rootView: makeStatusMenuContentView(provider: provider))
            popovers[provider] = popover
        }
    }

    func synchronizeProviderLifecycle() {
        for provider in UsageProvider.allCases {
            let previousTask = lifecycleTasks[provider]
            lifecycleTasks[provider] = Task { [weak self] in
                await previousTask?.value
                guard let self else { return }
                let enabled = enabledProviders.contains(provider)
                if provider == .codex { await setCodexEnabled(enabled) }
                else { await setClaudeEnabled(enabled) }
            }
        }
    }

    private func setCodexEnabled(_ enabled: Bool) async {
        if enabled {
            await store.start()
            if showsOpenAIUsage { await openAIUsageStore.start() }
        } else {
            await store.stop()
            await openAIUsageStore.stop()
        }
    }

    private func setClaudeEnabled(_ enabled: Bool) async {
        if enabled { await claudeUsageStore.start() }
        else { await claudeUsageStore.stop() }
    }

    func makeStatusMenuContentView(provider: UsageProvider = .codex) -> StatusMenuContentView {
        StatusMenuContentView(
            store: store,
            openAIUsageStore: openAIUsageStore,
            screenshotAppearance: screenshotConfiguration?.appearance,
            visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs,
            showsCredits: provider == .codex && showsCredits,
            showsOpenAIUsage: provider == .codex && showsOpenAIUsage,
            claudeUsageStore: provider == .claude ? claudeUsageStore : nil,
            provider: provider
        )
    }

    private func observeState() {
        withObservationTracking {
            _ = store.statusItemPresentation
            _ = store.statusBarText
            _ = store.statusBarAccessibilityText
            _ = store.statusItemTooltipText
            _ = store.state
            _ = store.statusMessage
            _ = store.cards.count
            _ = claudeUsageStore.statusItemPresentation
            _ = claudeUsageStore.statusItemTooltipText
            _ = claudeUsageStore.statusBarAccessibilityText
            _ = openAIUsageStore.viewData
            _ = loginItemController.isEnabled
            _ = loginItemController.statusMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.resizeVisiblePopovers()
                self?.maybeReportStartupDiagnostics()
                self?.observeState()
            }
        }
    }

    private func updateStatusItem() {
        for (provider, item) in statusItems {
            if let button = item.button { updateStatusItemButton(button, provider: provider) }
        }
    }

    var popoverContentSize: NSSize { popoverContentSize(for: screenshotProvider) }

    func popoverContentSize(for provider: UsageProvider) -> NSSize {
        let content = NSHostingView(rootView: makeStatusMenuContentView(provider: provider).naturalContent)
        return NSSize(width: 352, height: min(ceil(content.fittingSize.height), StatusMenuContentView.maximumPopoverHeight))
    }

    private func resizeVisiblePopovers() {
        for (provider, popover) in popovers where popover.isShown {
            popover.contentSize = popoverContentSize(for: provider)
        }
    }

    func updateStatusItemButton(_ button: NSStatusBarButton, provider: UsageProvider = .codex) {
        let presentation = provider == .codex ? store.statusItemPresentation : claudeUsageStore.statusItemPresentation
        switch presentation {
        case let .text(text):
            button.image = Self.statusItemImage(provider: provider)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.title = text
        case let .bar(bar):
            let palette = statusItemPalette(for: button)
            button.image = Self.readyStatusItemImage(
                bar: bar,
                appearance: button.effectiveAppearance,
                glyphColor: palette.statusItemGlyphColor,
                trackColor: palette.trackColor(for: bar.progressState),
                fillColor: palette.fillColor(for: bar.progressState),
                provider: provider
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.title = ""
        }
        button.toolTip = provider == .codex ? "Codex · " + store.statusItemTooltipText : claudeUsageStore.statusItemTooltipText
        button.setAccessibilityLabel(provider == .codex ? "Codex toolbar. \(store.statusBarAccessibilityText)" : claudeUsageStore.statusBarAccessibilityText)
        // NSStatusBar sizes variable-length items with native horizontal
        // padding. Calling sizeToFit() here removes that space and makes
        // adjacent providers' bars and icons touch.
    }
    private func maybeReportStartupDiagnostics() {
        guard
            let startupDiagnosticsConfiguration,
            !startupDiagnosticsDidFinish
        else {
            return
        }

        let record = StartupDiagnosticsRecord(
            store: store,
            loginItemStatus: loginItemController.statusMessage
        )

        do {
            let reporter = StartupDiagnosticsReporter(configuration: startupDiagnosticsConfiguration)
            try reporter.report(store: store, loginItemStatus: loginItemController.statusMessage)
        } catch {
            fputs("Startup diagnostics failed: \(error.localizedDescription)\n", stderr)
        }

        guard record.isValidFirstRunState else {
            return
        }

        startupDiagnosticsDidFinish = true

        if startupDiagnosticsConfiguration.terminateAfterFirstReport {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let provider = statusItems.first(where: { $0.value.button === sender })?.key else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender, provider: provider)
        } else {
            togglePopover(relativeTo: sender, provider: provider)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton, provider: UsageProvider) {
        guard let popover = popovers[provider] else { return }
        if popover.isShown { popover.performClose(nil) }
        else { showPopover(relativeTo: button, provider: provider) }
    }

    private func showPopover(relativeTo button: NSStatusBarButton, provider: UsageProvider) {
        guard let popover = popovers[provider] else { return }
        for (otherProvider, otherPopover) in popovers where otherProvider != provider { otherPopover.performClose(nil) }
        popover.contentSize = popoverContentSize(for: provider)
        if let controller = popover.contentViewController as? NSHostingController<StatusMenuContentView> {
            controller.rootView = makeStatusMenuContentView(provider: provider)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task {
            if provider == .claude {
                await claudeUsageStore.refreshIfNeeded()
            } else if showsOpenAIUsage {
                await openAIUsageStore.refreshIfNeeded(maxAge: OpenAIUsageStore.staleRefreshMaximumAge)
            }
        }
    }

    private func showContextMenu(from button: NSStatusBarButton, provider: UsageProvider) {
        popovers[provider]?.performClose(nil)
        let item = statusItems[provider]
        item?.menu = makeContextMenu(provider: provider)
        button.performClick(nil)
        item?.menu = nil
    }

    func makeContextMenu(provider: UsageProvider = .codex) -> NSMenu {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow(_:)), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.representedObject = provider.rawValue
        menu.addItem(refreshItem)

        let launchTitle = loginItemController.isEnabled ? "Disable launch at login" : "Launch at login"
        let launchItem = NSMenuItem(title: launchTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

        if provider == .codex {
            for family in GetAccountRateLimitsResponse.supportedSupplementalFamilies where family.isUserToggleable {
                let item = NSMenuItem(
                    title: "Show \(family.categoryLabel)",
                    action: #selector(toggleSupplementalFamilyVisibility(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.state = visibleSupplementalFamilyIDs.contains(family.limitId) ? .on : .off
                item.representedObject = family.limitId
                menu.addItem(item)
            }

            let showCreditsItem = NSMenuItem(
                title: "Show credits",
                action: #selector(toggleCreditsVisibility),
                keyEquivalent: ""
            )
            showCreditsItem.target = self
            showCreditsItem.state = showsCredits ? .on : .off
            menu.addItem(showCreditsItem)

            let showOpenAIUsageItem = NSMenuItem(
                title: "Show API usage",
                action: #selector(toggleOpenAIUsageVisibility),
                keyEquivalent: ""
            )
            showOpenAIUsageItem.target = self
            showOpenAIUsageItem.state = showsOpenAIUsage ? .on : .off
            menu.addItem(showOpenAIUsageItem)
        }

        let providersItem = NSMenuItem(title: "Choose providers…", action: #selector(chooseProviders), keyEquivalent: "")
        providersItem.target = self
        menu.addItem(providersItem)

        if provider == .codex, codexDesktopAppProvider.installedApplicationURL != nil {
            let openCodexItem = NSMenuItem(title: "Open Codex", action: #selector(openCodexApp), keyEquivalent: "")
            openCodexItem.target = self
            menu.addItem(openCodexItem)
        }

        if provider == .codex && openAIUsageStore.isEnabled {
            menu.addItem(.separator())

            let configureOpenAIKeyItem = NSMenuItem(
                title: "Configure OpenAI admin key…",
                action: #selector(configureOpenAIAdminKey),
                keyEquivalent: ""
            )
            configureOpenAIKeyItem.target = self
            menu.addItem(configureOpenAIKeyItem)

            let removeOpenAIKeyItem = NSMenuItem(
                title: "Remove OpenAI admin key",
                action: #selector(removeOpenAIAdminKey),
                keyEquivalent: ""
            )
            removeOpenAIKeyItem.target = self
            removeOpenAIKeyItem.isEnabled = openAIUsageStore.hasConfiguredAdminKey
            menu.addItem(removeOpenAIKeyItem)
        }

        menu.addItem(.separator())

        if let latestTag = gitUpdateController.menuState.latestTag {
            let availableItem = NSMenuItem(title: "Update available: \(latestTag)", action: nil, keyEquivalent: "")
            availableItem.isEnabled = false
            menu.addItem(availableItem)

            let actionTitle: String
            switch gitUpdateController.menuState.action {
            case .installFromGitCheckout:
                actionTitle = "Install update"
            case .downloadRelease:
                actionTitle = "Download update"
            case nil:
                actionTitle = "Install update"
            }

            let installUpdateItem = NSMenuItem(title: actionTitle, action: #selector(installUpdate), keyEquivalent: "")
            installUpdateItem.target = self
            menu.addItem(installUpdateItem)
        }

        let versionItem = NSMenuItem(title: "Version \(AppVersion.current)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func refreshNow(_ sender: NSMenuItem?) {
        let provider = (sender?.representedObject as? String).flatMap(UsageProvider.init(rawValue:)) ?? .codex
        Task { await refreshUsage(for: provider) }
    }

    func refreshUsage(for provider: UsageProvider) async {
        guard enabledProviders.contains(provider) else { return }
        if provider == .claude {
            await claudeUsageStore.refreshNow()
        } else {
            async let rateLimits: Void = store.refreshNow()
            async let updates: Void = gitUpdateController.refreshNow()
            if showsOpenAIUsage { await openAIUsageStore.refreshNow() }
            _ = await (rateLimits, updates)
        }
    }

    @objc private func chooseProviders() {
        for popover in popovers.values { popover.performClose(nil) }
        guard let choice = appRuntime.chooseUsageProviders(current: preferences.usageProviderSelection) else { return }
        preferences.setUsageProviderSelection(choice)
        configureProviderItems()
        updateStatusItem()
        synchronizeProviderLifecycle()
    }

    @objc private func toggleLaunchAtLogin() {
        loginItemController.setEnabled(!loginItemController.isEnabled)
    }

    @objc private func toggleSupplementalFamilyVisibility(_ sender: NSMenuItem) {
        guard
            let limitId = sender.representedObject as? String,
            let family = GetAccountRateLimitsResponse.supplementalFamily(for: limitId)
        else {
            return
        }

        preferences.toggleSupplementalFamilyVisibility(family)
    }

    @objc private func toggleCreditsVisibility() {
        preferences.toggleCreditsVisibility()
    }

    @objc private func toggleOpenAIUsageVisibility() {
        let isVisible = !showsOpenAIUsage
        preferences.setOpenAIUsageVisible(isVisible)

        Task {
            if isVisible {
                await openAIUsageStore.start()
            } else {
                await openAIUsageStore.stop()
            }
        }
    }

    @objc private func configureOpenAIAdminKey() {
        guard let adminKey = appRuntime.promptForSecret(
            title: "Configure OpenAI admin key",
            message: "Paste an OPENAI_ADMIN_KEY to fetch organization-level OpenAI API usage."
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !adminKey.isEmpty else {
            return
        }

        do {
            try openAIUsageStore.saveAdminKey(adminKey)
            if showsOpenAIUsage {
                Task {
                    await openAIUsageStore.refreshNow()
                }
            }
        } catch {
            appRuntime.postNotification(
                title: "OpenAI usage setup failed",
                body: error.localizedDescription
            )
        }
    }

    @objc private func removeOpenAIAdminKey() {
        do {
            try openAIUsageStore.removeAdminKey()
        } catch {
            appRuntime.postNotification(
                title: "OpenAI usage setup failed",
                body: error.localizedDescription
            )
        }
    }

    @objc private func installUpdate() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            handleInstallUpdateResult(await gitUpdateController.installUpdate())
        }
    }

    func handleInstallUpdateResult(_ result: GitUpdateInstallResult) {
        switch result {
        case .started:
            for popover in popovers.values { popover.performClose(nil) }
            appRuntime.terminate()
        case let .openReleasePage(url):
            do {
                try appRuntime.openURL(url)
                for popover in popovers.values { popover.performClose(nil) }
            } catch {
                appRuntime.postNotification(
                    title: "CodexToolbar update failed",
                    body: error.localizedDescription
                )
            }
        case let .failed(message):
            appRuntime.postNotification(title: "CodexToolbar update failed", body: message)
        }
    }

    @objc private func quitApp() {
        appRuntime.terminate()
    }

    private var visibleSupplementalFamilyIDs: Set<String> {
        if let visibleSupplementalFamilyIDs = screenshotConfiguration?.visibleSupplementalFamilyIDs {
            return visibleSupplementalFamilyIDs
        }

        return preferences.visibleSupplementalFamilyIDs()
    }

    private var showsCredits: Bool {
        preferences.isCreditsVisible
    }

    private var showsOpenAIUsage: Bool {
        preferences.isOpenAIUsageVisible
    }

    @objc private func openCodexApp() {
        guard codexDesktopAppProvider.installedApplicationURL != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.codexDesktopAppProvider.openCodex()
                self.closePopover()
            } catch {
                fputs("Open Codex failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private func closePopover() {
        if let popoverCloseHandler {
            popoverCloseHandler()
            return
        }

        popovers[.codex]?.performClose(nil)
    }

    private static func statusItemImage(provider: UsageProvider = .codex) -> NSImage {
        if provider == .claude {
            // Match Codex's full-size filled disc. The SF circle variant has
            // typographic margins that make it visibly smaller at 16 points.
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.saveGState()
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: rect)
                context.setBlendMode(.clear)
                context.setLineWidth(1.2)
                context.setLineCap(.round)
                for index in 0..<3 {
                    let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / 3
                    let dx = cos(angle) * 3.5
                    let dy = sin(angle) * 3.5
                    context.move(to: CGPoint(x: rect.midX - dx, y: rect.midY - dy))
                    context.addLine(to: CGPoint(x: rect.midX + dx, y: rect.midY + dy))
                }
                context.strokePath()
                context.restoreGState()
                return true
            }
            image.isTemplate = true
            return image
        }
        if let image = StatusItemAssetLoader.image(named: "CodexStatusGlyph") {
            image.isTemplate = false
            image.size = NSSize(width: 16, height: 16)
            return image
        }

        let fallback = NSImage(systemSymbolName: "greaterthan.circle", accessibilityDescription: "Codex")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = false
        fallback.size = NSSize(width: 16, height: 16)
        return fallback
    }

    private func statusItemPalette(for button: NSStatusBarButton) -> StatusMenuPalette {
        let colorScheme = Self.colorScheme(for: button.effectiveAppearance)
        return StatusMenuPalette.forAppearance(screenshotConfiguration?.appearance, colorScheme: colorScheme)
    }

    private static func colorScheme(for appearance: NSAppearance) -> ColorScheme {
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return .dark
        default:
            return .light
        }
    }

    static func readyStatusItemImage(
        bar: RateLimitStore.StatusItemBarPresentation,
        appearance: NSAppearance,
        glyphColor: NSColor,
        trackColor: NSColor,
        fillColor: NSColor,
        provider: UsageProvider = .codex
    ) -> NSImage {
        let glyphSize = NSSize(width: 16, height: 16)
        let gap: CGFloat = 4
        let barSize = NSSize(width: 44, height: 6)
        let imageSize = NSSize(width: glyphSize.width + gap + barSize.width, height: glyphSize.height)
        let image = NSImage(size: imageSize)
        let glyphRect = NSRect(
            x: 0,
            y: (imageSize.height - glyphSize.height) / 2,
            width: glyphSize.width,
            height: glyphSize.height
        )
        let barRect = NSRect(
            x: glyphSize.width + gap,
            y: (imageSize.height - barSize.height) / 2,
            width: barSize.width,
            height: barSize.height
        )

        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            drawTintedGlyph(in: glyphRect, color: glyphColor, provider: provider)
            drawBar(
                in: barRect,
                remainingPercent: bar.remainingPercent,
                trackColor: trackColor,
                fillColor: fillColor
            )
            image.unlockFocus()
        }
        image.isTemplate = false

        return image
    }

    private static func drawTintedGlyph(in rect: NSRect, color: NSColor, provider: UsageProvider) {
        let glyphImage = statusItemImage(provider: provider)
        glyphImage.draw(in: rect)
        color.setFill()
        rect.fill(using: .sourceIn)
    }

    private static func drawBar(
        in rect: NSRect,
        remainingPercent: Int,
        trackColor: NSColor,
        fillColor: NSColor
    ) {
        let radius = rect.height / 2
        let trackPath = NSBezierPath(
            roundedRect: rect,
            xRadius: radius,
            yRadius: radius
        )
        trackColor.setFill()
        trackPath.fill()

        guard remainingPercent > 0 else {
            return
        }

        let fillWidth = min(
            rect.width,
            max(rect.width * CGFloat(remainingPercent) / 100, 2)
        )
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: min(radius, fillRect.width / 2),
            yRadius: radius
        )
        fillColor.setFill()
        fillPath.fill()
    }

    private func scheduleScreenshotCaptureIfNeeded() {
        guard let screenshotConfiguration else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 350_000_000)

            if screenshotConfiguration.shouldOpenPopover, let button = statusItem?.button {
                showPopover(relativeTo: button, provider: screenshotProvider)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            do {
                try captureScreenshots(using: screenshotConfiguration)
            } catch {
                fputs("Screenshot capture failed: \(error.localizedDescription)\n", stderr)
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            NSApplication.shared.terminate(nil)
        }
    }

    private func captureScreenshots(using configuration: ScreenshotLaunchConfiguration) throws {
        guard let outputDirectory = configuration.outputDirectory else {
            return
        }

        let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if configuration.shouldCaptureStatusItem {
            try captureStatusItem(to: directoryURL, configuration: configuration)
        }

        if configuration.shouldCapturePopover {
            try capturePopover(to: directoryURL, configuration: configuration)
        }
    }

    private func captureStatusItem(to directoryURL: URL, configuration: ScreenshotLaunchConfiguration) throws {
        var captures: [(frame: NSRect, representation: NSBitmapImageRep)] = []
        for provider in enabledProviders {
            guard let button = statusItems[provider]?.button, let window = button.window else {
                throw ScreenshotCaptureError.unableToCaptureStatusItem
            }
            button.layoutSubtreeIfNeeded()
            let bounds = button.bounds.integral
            guard bounds.width > 0, bounds.height > 0,
                  let representation = button.bitmapImageRepForCachingDisplay(in: bounds) else {
                throw ScreenshotCaptureError.unableToCaptureStatusItem
            }
            button.cacheDisplay(in: bounds, to: representation)
            let frame = window.convertToScreen(button.convert(bounds, to: nil))
            captures.append((frame, representation))
            print("Status item \(provider.rawValue): button width \(bounds.width) pt, image width \(button.image?.size.width ?? 0) pt")
        }
        guard let first = captures.first else { return }
        // Preserve the actual native item positions so a paired capture can
        // expose missing inter-item spacing instead of hiding it in a crop.
        let captureBounds = captures.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        // Keep the native items on a transparent canvas without adding a
        // screenshot-only frame that contrasts with the surrounding page.
        let image = NSImage(size: captureBounds.size)
        image.lockFocus()
        for capture in captures {
            capture.representation.draw(
                in: capture.frame.offsetBy(
                    dx: -captureBounds.minX,
                    dy: -captureBounds.minY
                )
            )
        }
        image.unlockFocus()

        let fileURL = directoryURL.appendingPathComponent("\(configuration.scenario.name)-\(configuration.appearance.rawValue)-status-item.png")
        try Self.writePNG(image, to: fileURL)
    }

    private func capturePopover(to directoryURL: URL, configuration: ScreenshotLaunchConfiguration) throws {
        guard
            let popoverContentView = popover?.contentViewController?.view.window?.contentView
        else {
            return
        }

        popoverContentView.layoutSubtreeIfNeeded()

        let bounds = popoverContentView.bounds.integral
        guard
            bounds.width > 0,
            bounds.height > 0,
            let representation = popoverContentView.bitmapImageRepForCachingDisplay(in: bounds)
        else {
            throw ScreenshotCaptureError.unableToCapturePopover
        }

        popoverContentView.cacheDisplay(in: bounds, to: representation)

        let image = NSImage(size: bounds.size)
        image.lockFocus()
        representation.draw(in: NSRect(origin: .zero, size: bounds.size))
        image.unlockFocus()

        let fileURL = directoryURL.appendingPathComponent("\(configuration.scenario.name)-\(configuration.appearance.rawValue)-popover.png")
        try Self.writePNG(image, to: fileURL)
    }

    private static func writePNG(_ image: NSImage, to fileURL: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData) else {
            throw ScreenshotCaptureError.unableToEncodePNG
        }
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.unableToEncodePNG
        }

        try data.write(to: fileURL, options: .atomic)
    }
}

enum StatusItemAssetLoader {
    private static let resourceBundleDirectoryName = "CodexToolbar_CodexToolbar.bundle"

    static func image(
        named resourceName: String,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks,
        fileManager: FileManager = .default
    ) -> NSImage? {
        guard let bundle = resourceBundle(
            mainBundle: mainBundle,
            allBundles: allBundles,
            allFrameworks: allFrameworks,
            fileManager: fileManager
        ) else {
            return nil
        }

        return bundle.image(forResource: resourceName)
    }

    static func resourceBundle(
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks,
        fileManager: FileManager = .default
    ) -> Bundle? {
        for candidateURL in candidateBundleURLs(
            mainBundle: mainBundle,
            allBundles: allBundles,
            allFrameworks: allFrameworks
        ) {
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }

            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }

        return nil
    }

    static func candidateBundleURLs(
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> [URL] {
        var urls: [URL] = []
        var seenPaths = Set<String>()

        for bundle in [mainBundle] + allBundles + allFrameworks {
            register(resourceBundleURL(from: bundle), into: &urls, seenPaths: &seenPaths)

            let bundleURL = bundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL
            if bundleURL.lastPathComponent == resourceBundleDirectoryName {
                register(bundleURL, into: &urls, seenPaths: &seenPaths)
            }
        }

        return urls
    }

    private static func resourceBundleURL(from bundle: Bundle) -> URL? {
        guard let resourceURL = bundle.resourceURL else {
            return nil
        }

        return resourceURL
            .appendingPathComponent(resourceBundleDirectoryName, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private static func register(
        _ url: URL?,
        into urls: inout [URL],
        seenPaths: inout Set<String>
    ) {
        guard let url else {
            return
        }

        if seenPaths.insert(url.path).inserted {
            urls.append(url)
        }
    }
}

enum AppVersion {
    static let current: String = {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        if let version = developmentVersionFromSourceInfoPlist() {
            return version
        }

        return "0.1.16"
    }()

    private static func developmentVersionFromSourceInfoPlist() -> String? {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = repositoryRootURL.appendingPathComponent("Resources/Info.plist")

        guard
            let plist = NSDictionary(contentsOf: infoPlistURL),
            let version = plist["CFBundleShortVersionString"] as? String,
            !version.isEmpty
        else {
            return nil
        }

        return version
    }
}

private enum ScreenshotCaptureError: LocalizedError {
    case unableToCaptureStatusItem
    case unableToCapturePopover
    case unableToEncodePNG

    var errorDescription: String? {
        switch self {
        case .unableToCaptureStatusItem:
            return "Unable to capture the status item."
        case .unableToCapturePopover:
            return "Unable to capture the popover."
        case .unableToEncodePNG:
            return "Unable to encode screenshot PNG data."
        }
    }
}
