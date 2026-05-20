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
struct CodexToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: RateLimitStore
    private let openAIUsageStore: OpenAIUsageStore
    private let loginItemController: LoginItemController
    private let gitUpdateController: GitUpdateController
    private let codexDesktopAppProvider: any CodexDesktopAppProviding
    private let preferences: ToolbarPreferences
    private let maintenanceLaunchConfiguration: MaintenanceLaunchConfiguration?
    private let screenshotConfiguration: ScreenshotLaunchConfiguration?
    private let startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration?
    private let appRuntime: any AppRuntimeControlling
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
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
        startupDiagnosticsConfiguration = StartupDiagnosticsConfiguration.current()
        appRuntime = LiveAppRuntimeController()
        super.init()
    }

    init(
        store: RateLimitStore,
        openAIUsageStore: OpenAIUsageStore = OpenAIUsageStore(isEnabled: true),
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
        configureStatusItem()
        configurePopover()
        observeState()
        updateStatusItem()
        Task {
            await store.start()
        }
        Task {
            if showsOpenAIUsage {
                await openAIUsageStore.start()
            }
        }
        gitUpdateController.start()
        maybeReportStartupDiagnostics()
        scheduleScreenshotCaptureIfNeeded()
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

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Codex toolbar")
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = popoverContentSize
        popover.contentViewController = NSHostingController(rootView: makeStatusMenuContentView())
        self.popover = popover
    }

    func makeStatusMenuContentView() -> StatusMenuContentView {
        StatusMenuContentView(
            store: store,
            openAIUsageStore: openAIUsageStore,
            screenshotAppearance: screenshotConfiguration?.appearance,
            visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs,
            showsCredits: showsCredits,
            showsOpenAIUsage: showsOpenAIUsage,
            showsOpenCodexButton: shouldShowOpenCodexButton,
            openCodexAction: makeOpenCodexAction()
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
            _ = loginItemController.isEnabled
            _ = loginItemController.statusMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.maybeReportStartupDiagnostics()
                self?.observeState()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        updateStatusItemButton(button)
    }

    var popoverContentSize: NSSize {
        NSSize(width: 352, height: showsOpenAIUsage && openAIUsageStore.isEnabled ? 420 : 300)
    }

    func updateStatusItemButton(_ button: NSStatusBarButton) {
        switch store.statusItemPresentation {
        case let .text(text):
            button.image = Self.statusItemImage()
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
                fillColor: palette.fillColor(for: bar.progressState)
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.title = ""
        }

        button.toolTip = store.statusItemTooltipText
        button.setAccessibilityLabel("Codex toolbar. \(store.statusBarAccessibilityText)")
        button.sizeToFit()
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
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            showContextMenu(from: sender)
        default:
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }
        popover.contentSize = popoverContentSize
        if let controller = popover.contentViewController as? NSHostingController<StatusMenuContentView> {
            controller.rootView = makeStatusMenuContentView()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task {
            guard showsOpenAIUsage else {
                return
            }

            await openAIUsageStore.refreshIfNeeded(maxAge: OpenAIUsageStore.staleRefreshMaximumAge)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        popover?.performClose(nil)

        let menu = makeContextMenu()

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let launchTitle = loginItemController.isEnabled ? "Disable launch at login" : "Launch at login"
        let launchItem = NSMenuItem(title: launchTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

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

        if openAIUsageStore.isEnabled {
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

    @objc private func refreshNow() {
        Task {
            async let storeRefresh: Void = store.refreshNow()
            async let gitUpdateRefresh: Void = gitUpdateController.refreshNow()

            if showsOpenAIUsage {
                async let openAIUsageRefresh: Void = openAIUsageStore.refreshNow()
                _ = await (storeRefresh, openAIUsageRefresh, gitUpdateRefresh)
            } else {
                _ = await (storeRefresh, gitUpdateRefresh)
            }
        }
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
            popover?.performClose(nil)
            appRuntime.terminate()
        case let .openReleasePage(url):
            do {
                try appRuntime.openURL(url)
                popover?.performClose(nil)
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

    private var shouldShowOpenCodexButton: Bool {
        if let showsOpenCodexButton = screenshotConfiguration?.showsOpenCodexButton {
            return showsOpenCodexButton
        }

        return codexDesktopAppProvider.installedApplicationURL != nil
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

    private func makeOpenCodexAction() -> (() -> Void)? {
        guard shouldShowOpenCodexButton else {
            return nil
        }

        return { [weak self] in
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
    }

    private func closePopover() {
        if let popoverCloseHandler {
            popoverCloseHandler()
            return
        }

        popover?.performClose(nil)
    }

    private static func statusItemImage() -> NSImage {
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
        fillColor: NSColor
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
            drawTintedGlyph(in: glyphRect, color: glyphColor)
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

    private static func drawTintedGlyph(in rect: NSRect, color: NSColor) {
        let glyphImage = statusItemImage()
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
                showPopover(relativeTo: button)
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
        guard let button = statusItem?.button else {
            return
        }

        button.layoutSubtreeIfNeeded()

        let buttonBounds = button.bounds.integral
        guard
            buttonBounds.width > 0,
            buttonBounds.height > 0,
            let buttonRepresentation = button.bitmapImageRepForCachingDisplay(in: buttonBounds)
        else {
            throw ScreenshotCaptureError.unableToCaptureStatusItem
        }

        button.cacheDisplay(in: buttonBounds, to: buttonRepresentation)

        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 6
        let canvasSize = NSSize(
            width: buttonBounds.width + (horizontalPadding * 2),
            height: buttonBounds.height + (verticalPadding * 2)
        )

        let image = NSImage(size: canvasSize)
        image.lockFocus()
        backgroundColor(for: configuration.appearance).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
        buttonRepresentation.draw(
            in: NSRect(
                x: horizontalPadding,
                y: verticalPadding,
                width: buttonBounds.width,
                height: buttonBounds.height
            )
        )
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

    private func backgroundColor(for appearance: ScreenshotAppearance) -> NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.93, alpha: 1.0)
        case .dark:
            return NSColor(calibratedWhite: 0.24, alpha: 1.0)
        }
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

        return "0.1.14"
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
