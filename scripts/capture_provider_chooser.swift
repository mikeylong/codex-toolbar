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
        let timer = Timer(timeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated {
                defer { app.abortModal() }
                guard let view = chooser.alert.window.contentView else { return }
                view.layoutSubtreeIfNeeded()
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
