#!/usr/bin/env swift

import AppKit
import Foundation

struct MarketingShot {
    let filename: String
    let title: String
    let subtitle: String
    let callout: String
    let imageName: String
    let includeStatusItem: Bool
}

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let rawDirectory = rootURL.appendingPathComponent("AppStore/raw-screenshots")
let outputDirectory = rootURL.appendingPathComponent("AppStore/screenshots")

let shots: [MarketingShot] = [
    .init(
        filename: "01-at-a-glance-menu-bar-status.png",
        title: "At-a-glance menu bar status",
        subtitle: "Keep the most constrained window visible without opening a dashboard.",
        callout: "Status item + popover together",
        imageName: "normal-light-popover.png",
        includeStatusItem: true
    ),
    .init(
        filename: "02-live-window-breakdown.png",
        title: "Live window breakdown",
        subtitle: "Each window keeps remaining percentage, usage, and reset timing in one compact view.",
        callout: "Two windows, one popover",
        imageName: "warning-light-popover.png",
        includeStatusItem: false
    ),
    .init(
        filename: "03-reset-timing-and-progress.png",
        title: "Reset timing and progress",
        subtitle: "Progress bars and reset timestamps make it obvious when capacity returns.",
        callout: "Remaining percentage first",
        imageName: "critical-light-popover.png",
        includeStatusItem: false
    ),
    .init(
        filename: "04-launch-at-login.png",
        title: "Launch at login",
        subtitle: "Keep QuotaBar resident in the menu bar and available as soon as the desktop is ready.",
        callout: "Configured from the status menu",
        imageName: "normal-light-popover.png",
        includeStatusItem: false
    ),
    .init(
        filename: "05-demo-mode-for-review-and-setup.png",
        title: "Demo mode for review and setup",
        subtitle: "Deterministic sample scenarios make screenshots, QA, and App Review reproducible.",
        callout: "Powered by the demo scenario menu",
        imageName: "multiweek-light-popover.png",
        includeStatusItem: false
    )
]

let canvasSize = CGSize(width: 2880, height: 1800)

func loadImage(named name: String) throws -> NSImage {
    let url = rawDirectory.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "QuotaBarScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing input image: \(url.path)"])
    }
    return image
}

func attributed(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [
        .font: font,
        .foregroundColor: color
    ])
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawShadowedImage(_ image: NSImage, in rect: NSRect, cornerRadius: CGFloat) {
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 48
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    clipPath.addClip()
    image.draw(in: rect)
    NSGraphicsContext.current?.restoreGraphicsState()
}

func writeCanvas(to url: URL, drawing: (NSRect) -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "QuotaBarScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate bitmap."])
    }

    bitmap.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "QuotaBarScreenshots", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate graphics context."])
    }

    NSGraphicsContext.current = context
    drawing(NSRect(origin: .zero, size: canvasSize))

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "QuotaBarScreenshots", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to encode screenshot."])
    }

    try pngData.write(to: url, options: .atomic)
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let statusItemImage = NSImage(contentsOf: rawDirectory.appendingPathComponent("normal-light-status-item.png"))

for shot in shots {
    let preview = try loadImage(named: shot.imageName)
    try writeCanvas(to: outputDirectory.appendingPathComponent(shot.filename)) { canvas in
        let backgroundGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.17, alpha: 1.0),
            NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.27, alpha: 1.0)
        ])!
        backgroundGradient.draw(in: canvas, angle: 270)

        let glowPath = NSBezierPath(ovalIn: NSRect(x: 1920, y: 1180, width: 760, height: 520))
        NSColor(calibratedRed: 0.95, green: 0.53, blue: 0.25, alpha: 0.16).setFill()
        glowPath.fill()

        let accentRect = NSRect(x: 160, y: 1440, width: 320, height: 10)
        drawRoundedRect(accentRect, radius: 5, fill: NSColor(calibratedRed: 0.95, green: 0.53, blue: 0.25, alpha: 1.0))

        attributed(
            shot.title,
            font: NSFont.systemFont(ofSize: 112, weight: .bold),
            color: .white
        ).draw(in: NSRect(x: 160, y: 1040, width: 1160, height: 260))

        attributed(
            shot.subtitle,
            font: NSFont.systemFont(ofSize: 44, weight: .regular),
            color: NSColor(calibratedWhite: 0.88, alpha: 1.0)
        ).draw(in: NSRect(x: 168, y: 860, width: 1020, height: 180))

        let calloutRect = NSRect(x: 160, y: 640, width: 520, height: 86)
        drawRoundedRect(
            calloutRect,
            radius: 28,
            fill: NSColor(calibratedRed: 0.95, green: 0.53, blue: 0.25, alpha: 0.20),
            stroke: NSColor(calibratedRed: 0.95, green: 0.53, blue: 0.25, alpha: 0.35)
        )
        attributed(
            shot.callout,
            font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            color: NSColor(calibratedWhite: 0.97, alpha: 1.0)
        ).draw(in: calloutRect.insetBy(dx: 28, dy: 20))

        let frameRect = NSRect(x: 1420, y: 270, width: 1160, height: 1260)
        drawRoundedRect(
            frameRect,
            radius: 56,
            fill: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.24, alpha: 0.78),
            stroke: NSColor.white.withAlphaComponent(0.12),
            lineWidth: 2
        )

        let previewRect = NSRect(x: frameRect.minX + 180, y: frameRect.minY + 170, width: 704, height: preview.size.height * (704 / preview.size.width))
        drawShadowedImage(preview, in: previewRect, cornerRadius: 24)

        if shot.includeStatusItem, let statusItemImage {
            let statusStrip = NSRect(x: frameRect.minX + 240, y: frameRect.maxY - 250, width: 340, height: 64)
            drawRoundedRect(
                statusStrip,
                radius: 24,
                fill: NSColor(calibratedWhite: 1.0, alpha: 0.92)
            )
            statusItemImage.draw(in: statusStrip.insetBy(dx: 28, dy: 16))
        }

        attributed(
            "QuotaBar",
            font: NSFont.systemFont(ofSize: 28, weight: .bold),
            color: NSColor(calibratedWhite: 0.98, alpha: 1.0)
        ).draw(at: NSPoint(x: frameRect.minX + 74, y: frameRect.maxY - 98))

        attributed(
            "Independent macOS utility",
            font: NSFont.systemFont(ofSize: 24, weight: .medium),
            color: NSColor(calibratedWhite: 0.72, alpha: 1.0)
        ).draw(at: NSPoint(x: frameRect.minX + 74, y: frameRect.maxY - 136))
    }
}

print("Generated marketing screenshots in \(outputDirectory.path)")
