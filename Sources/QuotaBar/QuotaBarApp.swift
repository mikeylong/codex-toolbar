import AppKit
import Observation
import SwiftUI
import ToolbarCore

@main
struct QuotaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentation = ToolbarPresentation.quotaBar
    private lazy var store = RateLimitStore.makeShared(
        presentation: presentation,
        clientFactory: { QuotaBarRateLimitClient() }
    )
    private let loginItemController = LoginItemController.shared
    private let screenshotConfiguration = ScreenshotLaunchConfiguration.current()
    private let startupDiagnosticsConfiguration = StartupDiagnosticsConfiguration.current()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var startupDiagnosticsDidFinish = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel(presentation.statusItemAccessibilityLabel)
    }

    private func configurePopover() {
        let controller = NSHostingController(rootView: StatusMenuContentView(store: store, presentation: presentation))
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 352, height: 300)
        popover.contentViewController = controller
        self.popover = popover
    }

    private func observeState() {
        withObservationTracking {
            _ = store.statusBarText
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
        button.image = Self.statusItemImage()
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.title = store.statusBarText
        button.setAccessibilityLabel("\(presentation.statusItemAccessibilityLabel), \(store.statusBarText)")
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

        guard record.isValidFirstRunState(validErrorMessages: presentation.validStartupErrorMessages) else {
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        popover?.performClose(nil)

        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let demoMenuItem = NSMenuItem(title: "Demo scenario", action: nil, keyEquivalent: "")
        demoMenuItem.submenu = makeDemoScenarioMenu()
        menu.addItem(demoMenuItem)

        let launchTitle = loginItemController.isEnabled ? "Disable launch at login" : "Launch at login"
        let launchItem = NSMenuItem(title: launchTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func makeDemoScenarioMenu() -> NSMenu {
        let menu = NSMenu()
        let currentScenario = QuotaBarReviewDemo.scenarioName()
        let options: [(String, String?)] = [
            ("Off", nil),
            ("Normal", "normal"),
            ("Warning", "warning"),
            ("Critical", "critical"),
            ("Exhausted", "exhausted"),
            ("Weekly", "multiweek")
        ]

        for option in options {
            let item = NSMenuItem(title: option.0, action: #selector(selectDemoScenario(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.1 ?? ""
            item.state = currentScenario == option.1 || (currentScenario == nil && option.1 == nil) ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    @objc private func refreshNow() {
        Task {
            await store.refreshNow()
        }
    }

    @objc private func selectDemoScenario(_ sender: NSMenuItem) {
        let representedValue = sender.representedObject as? String
        QuotaBarReviewDemo.setScenarioName(representedValue?.isEmpty == true ? nil : representedValue)
        Task {
            await store.refreshNow()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        loginItemController.setEnabled(!loginItemController.isEnabled)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private static func statusItemImage() -> NSImage {
        if let image = QuotaBarResources.bundle.image(forResource: "QuotaBarStatusGlyph") {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "gauge.with.needle",
            accessibilityDescription: ToolbarPresentation.quotaBar.fallbackImageAccessibilityLabel
        ) ?? NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = true
        fallback.size = NSSize(width: 16, height: 16)
        return fallback
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

        guard let pngData = buttonRepresentation.representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.unableToEncodePNG
        }

        try pngData.write(to: directoryURL.appendingPathComponent("\(configuration.scenario.name)-\(configuration.appearance.rawValue)-status-item.png"))
    }

    private func capturePopover(to directoryURL: URL, configuration: ScreenshotLaunchConfiguration) throws {
        guard
            let popoverWindow = popover?.contentViewController?.view.window,
            let contentView = popoverWindow.contentView
        else {
            throw ScreenshotCaptureError.unableToCapturePopover
        }

        contentView.layoutSubtreeIfNeeded()

        let contentBounds = contentView.bounds.integral
        guard
            contentBounds.width > 0,
            contentBounds.height > 0,
            let representation = contentView.bitmapImageRepForCachingDisplay(in: contentBounds)
        else {
            throw ScreenshotCaptureError.unableToCapturePopover
        }

        contentView.cacheDisplay(in: contentBounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.unableToEncodePNG
        }

        try pngData.write(to: directoryURL.appendingPathComponent("\(configuration.scenario.name)-\(configuration.appearance.rawValue)-popover.png"))
    }
}

private enum QuotaBarResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
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
            return "Unable to encode screenshot output."
        }
    }
}
