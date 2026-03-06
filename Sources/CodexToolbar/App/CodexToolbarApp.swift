import AppKit
import SwiftUI

@main
struct CodexToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = RateLimitStore.shared
    @State private var loginItemController = LoginItemController.shared

    init() {
        Task {
            await RateLimitStore.shared.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuContentView(store: store, loginItemController: loginItemController)
        } label: {
            StatusBarLabelView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
