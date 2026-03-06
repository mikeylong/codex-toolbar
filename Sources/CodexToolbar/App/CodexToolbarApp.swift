import AppKit
import Observation
import SwiftUI

@main
struct CodexToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Task {
            await RateLimitStore.shared.start()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = RateLimitStore.shared
    private let loginItemController = LoginItemController.shared
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        observeState()
        updateStatusItem()
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
        let controller = NSHostingController(rootView: StatusMenuContentView(store: store))
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 352, height: 300)
        popover.contentViewController = controller
        self.popover = popover
    }

    private func observeState() {
        withObservationTracking {
            _ = store.statusBarText
            _ = loginItemController.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.observeState()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        button.image = Self.statusItemImage()
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.attributedTitle = NSAttributedString(string: store.statusBarText, attributes: attributes)
        button.setAccessibilityLabel("Codex toolbar, \(store.statusBarText)")
        button.sizeToFit()
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        popover?.performClose(nil)

        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

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

    @objc private func refreshNow() {
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
        if let image = Bundle.module.image(forResource: "CodexStatusGlyph") {
            image.isTemplate = true
            image.size = NSSize(width: 21, height: 21)
            return image
        }

        let fallback = NSImage(systemSymbolName: "greaterthan.circle", accessibilityDescription: "Codex")
            ?? NSImage(size: NSSize(width: 21, height: 21))
        fallback.isTemplate = true
        fallback.size = NSSize(width: 21, height: 21)
        return fallback
    }
}
