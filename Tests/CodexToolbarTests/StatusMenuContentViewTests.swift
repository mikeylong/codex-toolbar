import AppKit
import SwiftUI
import XCTest
@testable import CodexToolbar

final class StatusMenuContentViewTests: XCTestCase {
    func testDarkScreenshotPaletteUsesLightActionText() throws {
        let palette = StatusMenuPalette.forAppearance(.dark, colorScheme: .light)
        let actionTextColor = try XCTUnwrap(palette.actionTextColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionTextColor.redComponent, 0.94, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.greenComponent, 0.95, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.blueComponent, 0.97, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testLightScreenshotPaletteUsesDarkActionText() throws {
        let palette = StatusMenuPalette.forAppearance(.light, colorScheme: .dark)
        let actionTextColor = try XCTUnwrap(palette.actionTextColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionTextColor.redComponent, 0.13, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.greenComponent, 0.13, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.blueComponent, 0.15, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testLiveLightPaletteUsesStableNeutralActionHighlight() throws {
        let palette = StatusMenuPalette.forAppearance(nil, colorScheme: .light)
        let actionHighlightColor = try XCTUnwrap(palette.actionHighlightColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionHighlightColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.blueComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.alphaComponent, 0.12, accuracy: 0.01)
    }

    func testLiveDarkPaletteUsesStableNeutralActionHighlight() throws {
        let palette = StatusMenuPalette.forAppearance(nil, colorScheme: .dark)
        let actionHighlightColor = try XCTUnwrap(palette.actionHighlightColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionHighlightColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.blueComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.alphaComponent, 0.12, accuracy: 0.01)
    }
}
