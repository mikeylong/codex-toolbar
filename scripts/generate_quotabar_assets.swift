#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let statusGlyphURL = rootURL.appendingPathComponent("Sources/QuotaBar/Resources/QuotaBarStatusGlyph.png")
let iconOutputURL = rootURL.appendingPathComponent("AppStore/Resources/QuotaBar.icns")

let accentOrange = NSColor(calibratedRed: 0.96, green: 0.54, blue: 0.18, alpha: 1.0)
let accentRed = NSColor(calibratedRed: 0.94, green: 0.32, blue: 0.21, alpha: 1.0)
let accentCream = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.90, alpha: 1.0)
let backgroundTop = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.24, alpha: 1.0)
let backgroundBottom = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)

try fileManager.createDirectory(at: statusGlyphURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

func makeImage(size: CGSize, drawing: (NSRect) -> Void) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }
    drawing(NSRect(origin: .zero, size: size))
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let representation = NSBitmapImageRep(data: tiffData),
        let pngData = representation.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "QuotaBarAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG."])
    }

    try pngData.write(to: url, options: .atomic)
}

func drawGauge(in rect: NSRect, lineWidth: CGFloat, arcInset: CGFloat, monochrome: Bool) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) * 0.34 - arcInset
    let startAngle: CGFloat = 205
    let endAngle: CGFloat = -25

    let shadowColor = monochrome ? NSColor.black.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.18)
    shadowColor.setStroke()
    let shadowPath = NSBezierPath()
    shadowPath.lineWidth = lineWidth + 1
    shadowPath.lineCapStyle = .round
    shadowPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    shadowPath.stroke()

    let arcPath = NSBezierPath()
    arcPath.lineWidth = lineWidth
    arcPath.lineCapStyle = .round
    arcPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)

    if monochrome {
        NSColor.black.withAlphaComponent(0.84).setStroke()
        arcPath.stroke()
    } else {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        arcPath.addClip()
        let gradient = NSGradient(colors: [accentOrange, accentRed])!
        gradient.draw(in: NSRect(x: rect.minX, y: rect.midY - radius, width: rect.width, height: radius * 2), angle: 0)
        context.restoreGState()
    }

    let needleLength = radius * 0.92
    let needleAngle = CGFloat(-18.0) * (.pi / 180.0)
    let needleEnd = CGPoint(
        x: center.x + cos(needleAngle) * needleLength,
        y: center.y + sin(needleAngle) * needleLength
    )

    let needlePath = NSBezierPath()
    needlePath.lineWidth = lineWidth * 0.55
    needlePath.lineCapStyle = .round
    needlePath.move(to: center)
    needlePath.line(to: needleEnd)
    (monochrome ? NSColor.black.withAlphaComponent(0.9) : accentCream).setStroke()
    needlePath.stroke()

    let hubRect = NSRect(x: center.x - lineWidth * 0.55, y: center.y - lineWidth * 0.55, width: lineWidth * 1.1, height: lineWidth * 1.1)
    let hubPath = NSBezierPath(ovalIn: hubRect)
    (monochrome ? NSColor.black.withAlphaComponent(0.9) : accentCream).setFill()
    hubPath.fill()
}

let statusGlyph = makeImage(size: CGSize(width: 64, height: 64)) { rect in
    NSColor.clear.setFill()
    rect.fill()
    drawGauge(in: rect.insetBy(dx: 6, dy: 6), lineWidth: 5.5, arcInset: 0, monochrome: true)
}

try writePNG(statusGlyph, to: statusGlyphURL)

let iconsetURL = rootURL.appendingPathComponent("AppStore/Resources/QuotaBar.iconset")
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
    ("16x16", 16), ("16x16@2x", 32),
    ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024)
]

for (name, size) in iconSizes {
    let image = makeImage(size: CGSize(width: size, height: size)) { rect in
        NSColor.clear.setFill()
        rect.fill()

        let cardRect = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        let gradient = NSGradient(colors: [backgroundTop, backgroundBottom])!
        gradient.draw(in: cardPath, angle: 270)

        NSColor.white.withAlphaComponent(0.10).setStroke()
        cardPath.lineWidth = max(2, rect.width * 0.012)
        cardPath.stroke()

        let gaugeRect = cardRect.insetBy(dx: cardRect.width * 0.16, dy: cardRect.height * 0.16)
        drawGauge(in: gaugeRect, lineWidth: rect.width * 0.08, arcInset: rect.width * 0.02, monochrome: false)
    }

    try writePNG(image, to: iconsetURL.appendingPathComponent("icon_\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", iconOutputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "QuotaBarAssets", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}

print("Generated:")
print(statusGlyphURL.path)
print(iconOutputURL.path)
