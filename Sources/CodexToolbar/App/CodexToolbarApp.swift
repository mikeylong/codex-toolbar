import AppKit
import Darwin
import Observation
import SwiftUI

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
    private let loginItemController: LoginItemController
    private let codexDesktopAppProvider: any CodexDesktopAppProviding
    private let preferences: ToolbarPreferences
    private let maintenanceLaunchConfiguration: MaintenanceLaunchConfiguration?
    private let screenshotConfiguration: ScreenshotLaunchConfiguration?
    private let startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var startupDiagnosticsDidFinish = false
    var popoverCloseHandler: (() -> Void)?

    override init() {
        store = .shared
        loginItemController = .shared
        codexDesktopAppProvider = CodexDesktopAppController()
        preferences = .shared
        maintenanceLaunchConfiguration = MaintenanceLaunchConfiguration.current()
        screenshotConfiguration = ScreenshotLaunchConfiguration.current()
        startupDiagnosticsConfiguration = StartupDiagnosticsConfiguration.current()
        super.init()
    }

    init(
        store: RateLimitStore,
        loginItemController: LoginItemController,
        codexDesktopAppProvider: any CodexDesktopAppProviding,
        preferences: ToolbarPreferences = .shared,
        maintenanceLaunchConfiguration: MaintenanceLaunchConfiguration?,
        screenshotConfiguration: ScreenshotLaunchConfiguration?,
        startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration?
    ) {
        self.store = store
        self.loginItemController = loginItemController
        self.codexDesktopAppProvider = codexDesktopAppProvider
        self.preferences = preferences
        self.maintenanceLaunchConfiguration = maintenanceLaunchConfiguration
        self.screenshotConfiguration = screenshotConfiguration
        self.startupDiagnosticsConfiguration = startupDiagnosticsConfiguration
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
        popover.contentSize = NSSize(width: 352, height: 300)
        popover.contentViewController = NSHostingController(rootView: makeStatusMenuContentView())
        self.popover = popover
    }

    func makeStatusMenuContentView() -> StatusMenuContentView {
        StatusMenuContentView(
            store: store,
            screenshotAppearance: screenshotConfiguration?.appearance,
            visibleSupplementalFamilyIDs: visibleSupplementalFamilyIDs,
            showsOpenCodexButton: shouldShowOpenCodexButton,
            openCodexAction: makeOpenCodexAction()
        )
    }

    private func observeState() {
        withObservationTracking {
            _ = store.statusItemPresentation
            _ = store.statusBarText
            _ = store.statusBarAccessibilityText
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
        if let controller = popover.contentViewController as? NSHostingController<StatusMenuContentView> {
            controller.rootView = makeStatusMenuContentView()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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

        menu.addItem(.separator())

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
            await store.refreshNow()
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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
        if let image = Bundle.module.image(forResource: "CodexStatusGlyph") {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            return image
        }

        let fallback = NSImage(systemSymbolName: "greaterthan.circle", accessibilityDescription: "Codex")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = true
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
        let tintedGlyph = NSImage(size: glyphImage.size)

        tintedGlyph.lockFocus()
        glyphImage.draw(in: NSRect(origin: .zero, size: glyphImage.size))
        color.set()
        NSRect(origin: .zero, size: glyphImage.size).fill(using: .sourceAtop)
        tintedGlyph.unlockFocus()
        tintedGlyph.draw(in: rect)
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

enum AppVersion {
    static let current: String = {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        return "0.1.1"
    }()
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
