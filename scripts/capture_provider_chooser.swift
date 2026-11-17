import AppKit

// Compile with the production chooser and provider model. Like the panel
// captures, this renders native controls against a solid theme background
// because offscreen snapshots omit macOS window-material compositing.
@main
struct ProviderChooserCapture {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count == 3,
              ["light", "dark"].contains(CommandLine.arguments[1]) else {
            fputs("Usage: ProviderChooserCapture <light|dark> <output.png>\n", stderr)
            exit(1)
        }
        let appearance = CommandLine.arguments[1]
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        app.finishLaunching()
        let chooser = UsageProviderChooser(current: .both)
        var succeeded = false
        var activeSince: Date?
        let deadline = Date().addingTimeInterval(5)
        let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
            MainActor.assumeIsolated {
                let window = chooser.alert.window
                let button = chooser.alert.buttons[0]
                guard app.isActive, window.isKeyWindow else {
                    activeSince = nil
                    guard Date() < deadline else {
                        fputs("Chooser capture failed: window did not become active (appActive=\(app.isActive), windowKey=\(window.isKeyWindow)).\n", stderr)
                        timer.invalidate()
                        app.abortModal()
                        return
                    }
                    app.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                // AppKit activation is asynchronous. Allow an active display
                // cycle before snapshotting the accent-colored native controls.
                guard let activeSince else {
                    activeSince = Date()
                    return
                }
                guard Date().timeIntervalSince(activeSince) >= 0.2 else { return }
                timer.invalidate()
                defer { app.abortModal() }
                guard button.isEnabled, window.defaultButtonCell === button.cell else {
                    fputs("Chooser capture failed: Show usage is not the enabled default button.\n", stderr)
                    return
                }
                guard let view = window.contentView else { return }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                let bounds = view.bounds.integral
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
                view.cacheDisplay(in: bounds, to: bitmap)
                let image = NSImage(size: bounds.size)
                image.lockFocus()
                let shape = NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24)
                shape.addClip()
                NSColor(white: appearance == "dark" ? 0.14 : 0.94, alpha: 1).setFill()
                shape.fill()
                let controls = NSImage(size: bounds.size)
                controls.addRepresentation(bitmap)
                controls.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
                image.unlockFocus()
                guard let tiff = image.tiffRepresentation,
                      let rendered = NSBitmapImageRep(data: tiff),
                      let png = rendered.representation(using: .png, properties: [:]) else { return }
                do {
                    try png.write(to: output)
                    print("Captured \(appearance) chooser with active key window and enabled default button.")
                    succeeded = true
                } catch {
                    fputs("Chooser capture failed: \(error)\n", stderr)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        _ = chooser.runModal()
        exit(succeeded ? 0 : 1)
    }
}
