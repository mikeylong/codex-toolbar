import AppKit
import Foundation
import XCTest
@testable import CodexToolbar

@MainActor
final class StatusItemAssetLoaderTests: XCTestCase {
    func testResourceBundlePrefersAppContentsResourcesBundle() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let appBundleURL = try makeBundle(
            at: rootURL.appendingPathComponent("TestApp.app", isDirectory: true),
            packageType: "APPL"
        )
        let appResourceBundleURL = appBundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent("CodexToolbar_CodexToolbar.bundle", isDirectory: true)
        try makeResourceBundle(at: appResourceBundleURL)

        let mainBundle = try XCTUnwrap(Bundle(url: appBundleURL))

        let resolvedBundle = try XCTUnwrap(
            StatusItemAssetLoader.resourceBundle(
                mainBundle: mainBundle,
                allBundles: [],
                allFrameworks: []
            )
        )
        let image = StatusItemAssetLoader.image(
            named: "CodexStatusGlyph",
            mainBundle: mainBundle,
            allBundles: [],
            allFrameworks: []
        )

        XCTAssertEqual(
            resolvedBundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL,
            appResourceBundleURL.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertNotNil(image)
    }

    func testResourceBundleFallsBackToDiscoveredBundles() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let appBundleURL = try makeBundle(
            at: rootURL.appendingPathComponent("TestApp.app", isDirectory: true),
            packageType: "APPL"
        )
        let hostBundleURL = try makeBundle(
            at: rootURL.appendingPathComponent("TestHost.bundle", isDirectory: true),
            packageType: "BNDL"
        )
        let hostResourceBundleURL = hostBundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent("CodexToolbar_CodexToolbar.bundle", isDirectory: true)
        try makeResourceBundle(at: hostResourceBundleURL)

        let mainBundle = try XCTUnwrap(Bundle(url: appBundleURL))
        let hostBundle = try XCTUnwrap(Bundle(url: hostBundleURL))

        let resolvedBundle = try XCTUnwrap(
            StatusItemAssetLoader.resourceBundle(
                mainBundle: mainBundle,
                allBundles: [hostBundle],
                allFrameworks: []
            )
        )

        XCTAssertEqual(
            resolvedBundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL,
            hostResourceBundleURL.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    func testImageReturnsNilWhenResourceBundleIsMissing() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let appBundleURL = try makeBundle(
            at: rootURL.appendingPathComponent("TestApp.app", isDirectory: true),
            packageType: "APPL"
        )
        let mainBundle = try XCTUnwrap(Bundle(url: appBundleURL))

        let image = StatusItemAssetLoader.image(
            named: "CodexStatusGlyph",
            mainBundle: mainBundle,
            allBundles: [],
            allFrameworks: []
        )

        XCTAssertNil(image)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexToolbarStatusItemAssetLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeBundle(at bundleURL: URL, packageType: String) throws -> URL {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.mikelong.codextoolbar.tests.\(UUID().uuidString)</string>
            <key>CFBundleName</key>
            <string>\(bundleURL.deletingPathExtension().lastPathComponent)</string>
            <key>CFBundlePackageType</key>
            <string>\(packageType)</string>
        </dict>
        </plist>
        """
        try plist.write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        if packageType == "APPL" {
            try FileManager.default.createDirectory(
                at: contentsURL.appendingPathComponent("MacOS", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        return bundleURL
    }

    private func makeResourceBundle(at bundleURL: URL) throws {
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try makePNG(
            at: bundleURL.appendingPathComponent("CodexStatusGlyph.png"),
            color: .white
        )
    }

    private func makePNG(at fileURL: URL, color: NSColor) throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try pngData.write(to: fileURL, options: .atomic)
    }
}
